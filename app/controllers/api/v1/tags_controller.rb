# Legacy tags (frozen, plan §2.1), scoped (S3-L): the caller sees the global
# default tags plus their own; only their own non-default tags can change.
class Api::V1::TagsController < ApplicationController
  before_action :require_current_user!
  before_action :set_visible_tag, only: %i[ show update destroy ]
  before_action :require_own_tag, only: %i[ update destroy ]

  # GET /tags
  def index
    render json: Tag.visible_to(current_user)
  end

  # GET /tags/default_tags (any user_id param is ignored: defaults are global)
  def default_tags
    render json: Tag.where(default_tag: true)
  end

  # GET /tags/1
  def show
    render json: @tag
  end

  # POST /tags -> always the caller's own, never a default tag
  def create
    @tag = Tag.new(tag_params.merge(user_id: current_user.id, default_tag: false))
    return render_invalid_reference(:category_id) if @tag.category_id.present? && !Category.exists?(@tag.category_id)

    if @tag.save
      render json: @tag, status: :created
    else
      render json: @tag.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /tags/1
  def update
    return render_invalid_reference(:category_id) if tag_params[:category_id].present? && !Category.exists?(tag_params[:category_id])

    if @tag.update(tag_params)
      render json: @tag
    else
      render json: @tag.errors, status: :unprocessable_entity
    end
  end

  # DELETE /tags/1
  def destroy
    @tag.destroy!
  end

  private

  def set_visible_tag
    @tag = Tag.visible_to(current_user).find(params[:id])
  end

  # Default tags are visible to everyone but belong to no one.
  def require_own_tag
    render_forbidden unless @tag.user_id == current_user.id && !@tag.default_tag
  end

  def tag_params
    params.require(:tag).permit(:name, :category_id)
  end
end
