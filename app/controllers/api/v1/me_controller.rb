# GET /api/v1/me (plan S2): returns the caller's user, creating or linking it
# on first use (Users::KindeProvisioner, SR-1), with an empty financial profile.
#
# Optional `time_zone` (IANA name, the device's zone, PO-12) is stored only if
# the profile has none yet; an invalid value is ignored. Any other parameter,
# including an email, is ignored.
class Api::V1::MeController < ApplicationController
  def show
    result = Users::KindeProvisioner.new.call(sub: current_kinde_sub, access_token: current_access_token)
    profile = result.user.financial_profile
    store_time_zone(profile)

    render json: me_json(result.user, profile)
  rescue Users::KindeProvisioner::Conflict
    render json: { error: "account_link_required" }, status: :conflict
  rescue Kinde::UserProfileFetcher::Unavailable => e
    Rails.logger.warn("[auth] Kinde profile unavailable (#{e.message})")
    render json: { error: "profile_unavailable" }, status: :service_unavailable
  end

  private

  def store_time_zone(profile)
    zone = params[:time_zone]
    return if profile.time_zone.present? || !FinancialProfile.valid_time_zone?(zone)

    profile.update!(time_zone: zone)
  end

  def me_json(user, profile)
    {
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      picture: user.picture,
      onboarding_completed: profile.onboarding_completed?,
      profile: { week_starts_on: profile.week_starts_on, time_zone: profile.time_zone }
    }
  end
end
