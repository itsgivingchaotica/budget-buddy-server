class Api::V1::EntriesController < ApplicationController
  before_action :set_entry, only: %i[ show update destroy ]

  # GET /entries
  def index
    @entries = Entry.all

    render json: @entries
  end

  # GET /entries/1
  def show
    render json: @entry
  end
# GET /entries/entries_by_budget_with_default_categories
def entries_by_budget_with_default_categories
  # Fetch budget ID and category ID from parameters
  budget_id = params[:budget_id]
  category_id = params[:category_id]

  # Fetch entries using joins between entries_tags and tags, and filtering by budget_id and category_id
  if category_id
    entries = Entry.joins(entries_tags: :tag)  # Join entries_tags and tag
                   .where(entries_tags: { budget_id: budget_id })
                   .where(tags: { category_id: category_id })  # Filter by category_id in tags
                   .includes(:tags)  # Include tags to avoid N+1 queries
                   .select('entries.*, tags.*')  # Select both entries and tags fields
  else
    # If no category_id is provided, fetch entries for all default categories for the given budget
    default_category_ids = Category.where(identifier: 'default').pluck(:id)
    entries = Entry.joins(entries_tags: :tag)
                   .where(entries_tags: { budget_id: budget_id })
                   .where(tags: { category_id: default_category_ids })
                   .includes(:tags)
                   .select('entries.*, tags.*')
  end

  # Render the entries and associated tags
  render json: entries.as_json(include: { tags: { only: [:id, :name] } })
end

  # POST /entries
  def create
    @entry = Entry.new(entry_params)

    if @entry.save
      params[:entry][:tag_ids].each do |tag_id|
        tag = Tag.find(tag_id)
        @entry.tags << tag unless @entry.tags.include?(tag)
        end
        Rails.logger.info("entry saved #{@entry.category_id}")
      render json: @entry, status: :created
    else
      render json: @entry.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /entries/1
  def update
    if @entry.update(entry_params)
      render json: @entry
    else
      render json: @entry.errors, status: :unprocessable_entity
    end
  end

  # DELETE /entries/1
  def destroy
    @entry.destroy!
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_entry
      @entry = Entry.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def entry_params
      params.require(:entry).permit(:budget_id, :start_date, :amount, :description, :frequency, :custom_frequency_days, :category_id, :frequency_number, :end_date, :tag_ids)
    end

    #  budget_id: budget.id,
    #   start_date: entryData.start_date,
    #   amount: entryData.amount,
    #   description: entryData.description,
    #   frequency: entryData.frequency,
    #   custom_frequency_days: entryData.custom_frequency_days,
    #   category_id: CategoryIdMap[selectedCategory],
    #   frequency_number: entryData.frequency_number,
    #   end_date: entryData.end_date,
    #   tag_ids: tagId, // matching join table for entries_tags
end