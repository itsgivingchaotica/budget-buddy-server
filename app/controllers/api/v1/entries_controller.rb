# Legacy entries (frozen, plan §2.1), scoped through the caller's budgets (S3-L).
# A budget_id the caller doesn't own -> 404; an unknown category or a tag the
# caller can't see -> 422.
class Api::V1::EntriesController < ApplicationController
  before_action :require_current_user!
  before_action :set_entry, only: %i[ show update destroy ]
  before_action :check_references, only: %i[ create update ]

  # GET /entries
  def index
    render json: entries_scope
  end

  # GET /entries/1
  def show
    render json: @entry
  end

  # GET /entries/entries_by_budget_with_default_categories?budget_id=&category_id=
  # Entries in one of the caller's budgets whose tags belong to the category.
  def entries_by_budget_with_default_categories
    budget = current_user.budgets.find(params[:budget_id])

    entries = budget.entries
                    .joins(:tags)
                    .where(tags: { category_id: params[:category_id] })
                    .distinct
                    .includes(:tags)

    render json: entries.as_json(include: { tags: { only: [:id, :name, :category_id] } })
  end

  # POST /entries
  def create
    @entry = Entry.new(entry_params.except(:tag_ids))

    if @entry.save
      sync_tags
      render json: @entry.as_json(include: :tags), status: :created
    else
      render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /entries/1
  def update
    if @entry.update(entry_params.except(:tag_ids))
      sync_tags if entry_params.key?(:tag_ids)
      render json: @entry.as_json(include: :tags)
    else
      render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /entries/1
  def destroy
    @entry.destroy!
  end

  private
    def entries_scope
      Entry.where(budget_id: current_user.budgets.select(:id))
    end

    def set_entry
      @entry = entries_scope.find(params[:id])
    end

    # Runs before any write: the target budget must be the caller's (404),
    # and referenced categories/tags must exist and be visible (422).
    def check_references
      # A blank budget_id is left to the model's validation (422).
      current_user.budgets.find(entry_params[:budget_id]) if entry_params[:budget_id].present?

      category_id = entry_params[:category_id]
      return render_invalid_reference(:category_id) if category_id.present? && !Category.exists?(category_id)

      tag_ids = Array(entry_params[:tag_ids]).compact_blank
      render_invalid_reference(:tag_ids) if tag_ids.any? && visible_tags.where(id: tag_ids).count != tag_ids.uniq.size
    end

    def visible_tags
      Tag.visible_to(current_user)
    end

    def entry_params
      params.require(:entry).permit(
        :budget_id,
        :start_date,
        :amount,
        :description,
        :frequency,
        :custom_frequency_days,
        :category_id,
        :frequency_number,
        :end_date,
        tag_ids: []
      )
    end

    def sync_tags
      @entry.tags = visible_tags.where(id: entry_params[:tag_ids].to_a)
    end
end
