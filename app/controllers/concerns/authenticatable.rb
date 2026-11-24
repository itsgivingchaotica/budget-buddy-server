# frozen_string_literal: true

# Requires a valid Kinde access token on every request (plan task S1b).
#
# The client sends `Authorization: Bearer <access token>`. The token is checked
# by Kinde::TokenVerifier (RS256 signature, iss, exp/nbf, sub and the API
# audience, which is required here). On success the verified claims are
# available as `current_auth_claims` / `current_kinde_sub`; S2 maps the `sub`
# to a User.
#
# Responses never say why a token was rejected, and logs record only the
# reason code: never the token or the Authorization header.
module Authenticatable
  extend ActiveSupport::Concern

  UNAUTHORIZED_BODY = { error: "unauthorized" }.freeze
  UNAVAILABLE_BODY = { error: "authentication_unavailable" }.freeze
  VERIFIER_LOCK = Mutex.new

  class << self
    # One verifier per process, so its key cache and refresh rate limits
    # actually apply (S1a security review). Raises
    # Kinde::TokenVerifier::ConfigurationError if KINDE_ISSUER_URL or
    # KINDE_AUDIENCE is missing.
    def verifier
      @verifier || VERIFIER_LOCK.synchronize do
        @verifier ||= Kinde::TokenVerifier.from_env(require_audience: true)
      end
    end

    # Tests install a verifier with a fake key fetcher; nil resets it.
    def verifier=(verifier)
      VERIFIER_LOCK.synchronize { @verifier = verifier }
    end
  end

  included do
    before_action :authenticate!
  end

  private

  attr_reader :current_auth_claims

  def current_kinde_sub
    current_auth_claims&.fetch("sub")
  end

  def authenticate!
    @current_auth_claims = Authenticatable.verifier.verify(bearer_token)
  rescue Kinde::TokenVerifier::InvalidToken => e
    Rails.logger.info("[auth] rejected request: #{e.reason}")
    response.set_header("WWW-Authenticate", 'Bearer realm="budget-buddy"')
    render json: UNAUTHORIZED_BODY, status: :unauthorized
  rescue Kinde::TokenVerifier::KeysUnavailable
    Rails.logger.warn("[auth] Kinde signing keys unavailable")
    render json: UNAVAILABLE_BODY, status: :service_unavailable
  end

  # Returns the token from `Authorization: Bearer <token>`, or nil (the
  # verifier then rejects it as :missing). The scheme is case-insensitive.
  def bearer_token
    scheme, token = request.authorization.to_s.split(" ", 2)
    return nil unless scheme&.casecmp?("Bearer")

    token&.strip
  end
end
