# Legacy budgets (frozen, plan §2.1), scoped to the caller (S3-L).
class Api::V1::BudgetsController < ApplicationController
  before_action :require_current_user!
  before_action :set_budget, only: %i[ show update destroy ]

  # GET /budgets
  def index
    render json: current_user.budgets
  end

  # GET /budgets/1
  def show
    render json: @budget
  end

  # POST /budgets (any user_id in the body is ignored)
  def create
    @budget = current_user.budgets.new(budget_params)

    if @budget.save
      render json: @budget, status: :created
    else
      render json: @budget.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /budgets/1
  def update
    if @budget.update(budget_params)
      render json: @budget
    else
      render json: @budget.errors, status: :unprocessable_entity
    end
  end

  # DELETE /budgets/1
  def destroy
    @budget.destroy!
  end

  private
    def set_budget
      @budget = current_user.budgets.find(params[:id])
    end

    def budget_params
      params.require(:budget).permit(:name)
    end
end
