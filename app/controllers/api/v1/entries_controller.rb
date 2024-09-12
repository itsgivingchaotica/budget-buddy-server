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
    # Fetch budget ID from parameters
    budget_id = params[:budget_id]
    
    # Fetch default category IDs
    default_category_ids = Category.where(identifier: 'default').pluck(:id)
    
    # Fetch entries with these category IDs and for the specific budget
    entries = Entry.where(category_id: default_category_ids, budget_id: budget_id).includes(:category)
    
    # Combine entries with category details if needed
    entries_with_category = entries.map do |entry|
      {
        entry: entry.attributes,
        category: entry.category.present? ? entry.category.attributes : {} # Adjust to handle case where category might be nil
      }
    end
    
    render json: entries_with_category
  end

  # POST /entries
  def create
    @entry = Entry.new(entry_params)

    if @entry.save
      render json: @entry, status: :created, location: @entry
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
      params.require(:entry).permit(:budget_id, :entry_type, :date, :amount, :description, :frequency, :custom_frequency_days)
    end
end
