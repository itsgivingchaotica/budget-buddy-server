class Api::V1::TagsController < ApplicationController
  # GET /tags
  def index
    @tags = Tag.all
    render json: @tags
  end

  def default_tags
    @default_tags = Tag.where(default_tag: true, user_id: 1)
    render json: @default_tags
  end

  # GET /tags/1
  def show
    @tag = Tag.find(params[:id])
    render json: @tag
  end

  # POST /tags
  def create
    @tag = Tag.new(tag_params)

    if @tag.save
      render json: @tag, status: :created, location: @tag
    else
      render json: @tag.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /tags/1
  def update
    @tag = Tag.find(params[:id])

    if @tag.update(tag_params)
      render json: @tag
    else
      render json: @tag.errors, status: :unprocessable_entity
    end
  end

  # DELETE /tags/1
  def destroy
    @tag = Tag.find(params[:id])
    @tag.destroy!
  end

  private

  # Only allow a list of trusted parameters through.
  def tag_params
    params.require(:tag).permit(:name)
  end
end
