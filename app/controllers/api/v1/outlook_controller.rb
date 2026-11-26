# W1 (Home outlook): GET /outlook/week, the caller's week (SPEC_LEFT_TO_SPEND §9).
# No parameters; money as strings.
class Api::V1::OutlookController < ApplicationController
  include MoneyJson
  include AnalyticsJson

  before_action :require_current_user!

  def week
    render json: analytics_json(WeeklyOutlook.call(current_user))
  end
end
