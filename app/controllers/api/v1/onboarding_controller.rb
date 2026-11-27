# ON1 (onboarding interview), SPEC_ONBOARDING_PLAN §4: the caller's own
# onboarding only (there are no ids). Money as strings.
#
#   GET /onboarding            step, facts from imported data, the questions
#                              (Rails-templated text, prefilled) and saved answers
#   PUT /onboarding/answers    { step?, pay?, side_income?, bills?, goals?,
#                                change_appetite?, follow_ups? } partial;
#                                validated per question; all or nothing
#   POST /onboarding/follow_ups  ON2: 0–2 coach follow-ups with Rails options
#                                (asked once and stored; never an error: no
#                                follow-ups when the AI is unavailable)
class Api::V1::OnboardingController < ApplicationController
  include MoneyJson
  include AnalyticsJson

  before_action :require_current_user!

  def show
    render json: analytics_json(Onboarding::Interview.state(current_user))
  end

  def follow_ups
    render json: { follow_ups: analytics_json(Onboarding::FollowUps.call(current_user)) }
  end

  def answers
    Onboarding::Interview.save!(current_user, params.permit!.slice(*%w[step pay side_income bills goals change_appetite follow_ups]))
    render json: analytics_json(Onboarding::Interview.state(current_user))
  rescue Onboarding::Interview::Invalid => e
    render json: { error: "invalid", errors: e.errors }, status: :unprocessable_entity
  end
end
