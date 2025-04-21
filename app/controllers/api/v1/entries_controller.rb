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

    # Get the entries filtered by the selected category only
    entries = Entry.joins(:tags)
                  .where(budget_id: budget_id)
                  .where(tags: { category_id: category_id })  # Only entries tagged with the selected category
               .distinct
               .includes(:tags)


    # Rails.logger.debug "Fetched entries with tags:\n" + JSON.pretty_generate(
    #   entries.as_json(
    #     include: {
    #       tags: { only: [:id, :name, :category_id] }
    #     }
    #   )
    # )
      render json: entries.as_json(
      include: {
        tags: { only: [:id, :name, :category_id] }
      }
    )
  end
  # POST /entries
  def create
  @entry = Entry.new(entry_params)

    if @entry.save
      # Add tags to the entry
      params[:entry][:tag_ids].each do |tag_id|
        tag = Tag.find(tag_id)
        @entry.tags << tag unless @entry.tags.include?(tag)
      end
      # Rails.logger.info("entry saved #{@entry.category_id}")
      render json: @entry.as_json(include: :tags), status: :created
    else
      Rails.logger.debug(@entry.errors.full_messages)  
      render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity
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
      tag_ids: [] # This allows an array of tag IDs
    )
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
    #   tag_ids: [tagId], // matching join table for entries_tags
end