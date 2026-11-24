# Categories are global reference data: any signed-in caller can read them;
# nobody can change them through the API (S3-L; the flat list comes from
# seeds, DM-1).
class Api::V1::CategoriesController < ApplicationController
  before_action :render_forbidden, only: %i[ create update destroy ]

  # GET /categories
  def index
    render json: Category.all
  end

  # GET /categories/1
  def show
    render json: Category.find(params[:id])
  end

  # GET /categories/default
  def default
    render json: Category.where(category_type: 'default')
  end

  def create; end
  def update; end
  def destroy; end
end
