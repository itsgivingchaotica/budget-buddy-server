# frozen_string_literal: true

module Users
  # Finds, links or creates the User for a verified Kinde identity (plan S2),
  # and makes sure that user has exactly one FinancialProfile.
  #
  # SR-1, account linking. An existing user row is linked to a Kinde `sub`
  # only if ALL of these hold:
  #   (a) the email comes from Kinde's user-profile endpoint, called
  #       server-side with the caller's verified token (never from the request);
  #   (b) Kinde reports `email_verified: true` (a missing field means no link);
  #   (c) the row has no kinde_id yet (an existing kinde_id is never overwritten);
  #   (d) the email matches ignoring case.
  # If an email matches but any condition fails, nothing is linked or created:
  # Conflict is raised (HTTP 409; a manual, approved link is needed).
  # Links are logged with user id and sub only: never the email or token.
  class KindeProvisioner
    class Conflict < StandardError; end

    Result = Struct.new(:user, :status, keyword_init: true) # status: :existing, :linked, :created

    def initialize(profile_fetcher: Kinde::UserProfileFetcher.default, logger: Rails.logger)
      @profile_fetcher = profile_fetcher
      @logger = logger
    end

    def call(sub:, access_token:)
      raise ArgumentError, "sub is required" if sub.blank?

      result = find_existing(sub) || link_or_create(sub, access_token)
      ensure_profile!(result.user)
      result
    end

    private

    def find_existing(sub)
      user = User.find_by(kinde_id: sub)
      Result.new(user: user, status: :existing) if user
    end

    def link_or_create(sub, access_token)
      profile = @profile_fetcher.call(access_token)
      profile_sub = profile["id"] || profile["sub"]
      raise Kinde::UserProfileFetcher::Unavailable, "Kinde profile does not match the token subject" unless profile_sub == sub

      email = profile["email"].is_a?(String) ? profile["email"].strip.presence : nil
      match = User.find_by_email_ci(email)

      return link!(match, sub, verified: profile["email_verified"] == true) if match

      create!(sub, email, profile)
    rescue ActiveRecord::RecordNotUnique
      # A concurrent first request for the same sub (or email) won the race.
      find_existing(sub) || raise(Conflict, "Account already exists")
    end

    def link!(user, sub, verified:)
      if !verified
        refuse!(user, sub, "email_not_verified")
      elsif user.kinde_id.present?
        refuse!(user, sub, "already_linked")
      end

      # Conditional update so a concurrent link can't overwrite a kinde_id.
      linked = User.where(id: user.id, kinde_id: nil).update_all(kinde_id: sub, updated_at: Time.current)
      refuse!(user, sub, "already_linked") if linked.zero?

      @logger.info("[auth] linked user_id=#{user.id} to sub=#{sub}")
      Result.new(user: user.reload, status: :linked)
    end

    def refuse!(user, sub, reason)
      @logger.info("[auth] link refused user_id=#{user.id} sub=#{sub} reason=#{reason}")
      raise Conflict, reason
    end

    def create!(sub, email, profile)
      user = User.create!(
        kinde_id: sub,
        email: email,
        first_name: string_or_nil(profile["given_name"]),
        last_name: string_or_nil(profile["family_name"]),
        picture: string_or_nil(profile["picture"])
      )
      @logger.info("[auth] created user_id=#{user.id} for sub=#{sub}")
      Result.new(user: user, status: :created)
    end

    def ensure_profile!(user)
      user.financial_profile || user.create_financial_profile!
    rescue ActiveRecord::RecordNotUnique
      user.reload.financial_profile
    end

    def string_or_nil(value)
      value.is_a?(String) ? value.strip.presence : nil
    end
  end
end
