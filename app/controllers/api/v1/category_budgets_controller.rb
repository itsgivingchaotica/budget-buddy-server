# DM-3 (category budgets): the caller's monthly budgets per flexible
# category. Every row is scoped to current_user; categories are referenced
# by slug from the shared list (unknown → 422, not flexible → 422).
#
#   GET /category_budgets?month=YYYY-MM   budgets in effect that month
#                                         (default: this month, user's zone)
#   PUT /category_budgets                 { month, budgets: [{ category, amount }] }
#                                         set several from that month on, all
#                                         or nothing (plan approval, PL2)
#   PUT /category_budgets/:category_slug  { amount } change one, from this
#                                         month (Plan → change a budget, C8)
#   GET /category_budgets/:category_slug/context[?amount=]
#                                         the change-a-budget sheet's figures
#                                         (AN1): weekly equivalent of the amount
#                                         (default: this month's budget), average
#                                         of the last 3 full months, spent this month
class Api::V1::CategoryBudgetsController < ApplicationController
  include MoneyJson
  include AnalyticsJson

  before_action :require_current_user!

  def index
    month = parse_month(params[:month]) or return
    render json: month_json(month)
  end

  def replace_month
    month = parse_month(params[:month]) or return
    entries = Array(params[:budgets])
    return render json: { error: "budgets_required" }, status: :unprocessable_entity if entries.empty?

    rows = entries.map do |entry|
      category = Category.active_list.find_by(slug: entry[:category].to_s)
      return render_invalid_reference("category") if category.nil?

      [category, entry[:amount]]
    end
    CategoryBudget.transaction { rows.each { |category, amount| upsert!(category, amount, month) } }
    render json: month_json(month)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid", errors: e.record.errors }, status: :unprocessable_entity
  end

  def update
    category = Category.active_list.find_by(slug: params[:category_slug].to_s)
    return render_invalid_reference("category") if category.nil?

    month = UserClock.month_start(current_user)
    upsert!(category, params[:amount], month)
    render json: category_json(category, CategoryBudget.in_effect_on(current_user, month).find_by(category:))
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid", errors: e.record.errors }, status: :unprocessable_entity
  end

  def context
    category = Category.active_list.find_by(slug: params[:category_slug].to_s)
    return render_invalid_reference("category") if category.nil?
    unless Category.flexible.exists?(category.id)
      return render json: { error: "not_flexible", field: "category" }, status: :unprocessable_entity
    end

    amount = if params[:amount].present?
               parse_amount(params[:amount])
             else
               CategoryBudget.in_effect_on(current_user, UserClock.month_start(current_user)).find_by(category:)&.amount
             end
    if params[:amount].present? && (amount.nil? || amount.negative? || amount > CategoryBudget::MAX_AMOUNT)
      return render json: { error: "invalid_parameter", field: "amount" }, status: :unprocessable_entity
    end

    render json: analytics_json(SpendingAnalytics.category_context(current_user, category, amount:))
  end

  private

  # "2026-11" → Date(2026-11-01); blank → this month in the user's zone.
  def parse_month(value)
    return UserClock.month_start(current_user) if value.blank?

    Date.strptime(value.to_s, "%Y-%m").beginning_of_month
  rescue Date::Error
    render json: { error: "invalid_parameter", field: "month" }, status: :unprocessable_entity
    nil
  end

  def upsert!(category, amount, month)
    budget = current_user.category_budgets.find_or_initialize_by(category:, effective_from: month)
    budget.amount = parse_amount(amount)
    budget.source = "user"
    budget.save!
  end

  def parse_amount(value)
    BigDecimal(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def month_json(month)
    in_effect = CategoryBudget.in_effect_on(current_user, month).index_by(&:category_id)
    budgets = Category.flexible.order(:position, :id).map { |c| category_json(c, in_effect[c.id]) }
    total = in_effect.values.sum(&:amount)
    { month: month.strftime("%Y-%m"), total: money(total), budgets: }
  end

  def category_json(category, budget)
    { category: category.slug, name: category.name, amount: budget && money(budget.amount),
      effective_from: budget&.effective_from }
  end
end
