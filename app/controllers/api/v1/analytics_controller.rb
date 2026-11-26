# AN2 (spending analytics API): SpendingAnalytics for the caller only. No
# budget or user in the path; every figure comes from AN1. Money as strings.
#
#   GET /analytics/summary?from=YYYY-MM-DD&to=YYYY-MM-DD[&category=slug]
#       spending and income in the range (≤ 366 days), with the same-length
#       previous period and the change
#   GET /analytics/budget_vs_actual?month=YYYY-MM   (default: this month)
class Api::V1::AnalyticsController < ApplicationController
  include MoneyJson
  include AnalyticsJson

  MAX_DAYS = 366

  before_action :require_current_user!

  def summary
    from = parse_date(:from) or return
    to = parse_date(:to) or return
    return invalid(:to) if to < from || (to - from).to_i >= MAX_DAYS

    category = nil
    if params[:category].present?
      category = Category.active_list.find_by(slug: params[:category].to_s)
      return render_invalid_reference("category") if category.nil?
    end
    render json: analytics_json(SpendingAnalytics.summary(current_user, from:, to:, category:))
  end

  def budget_vs_actual
    month = if params[:month].present?
              begin
                Date.strptime(params[:month].to_s, "%Y-%m")
              rescue Date::Error
                return invalid(:month)
              end
            else
              UserClock.month_start(current_user)
            end
    render json: analytics_json(SpendingAnalytics.budget_vs_actual(current_user, month:))
  end

  private

  def parse_date(field)
    Date.iso8601(params[field].to_s)
  rescue Date::Error
    invalid(field)
    nil
  end

  def invalid(field)
    render json: { error: "invalid_parameter", field: field.to_s }, status: :unprocessable_entity
  end
end
