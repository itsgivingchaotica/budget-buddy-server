# frozen_string_literal: true

require "json"
require "net/http"

module Kinde
  # Fetches the signed-in user's profile from Kinde, server-side, with the
  # caller's own (already verified) access token:
  #   GET <issuer>/oauth2/v2/user_profile   Authorization: Bearer <token>
  #
  # This is the server-verified email source for account linking (SR-1):
  # the email never comes from the request body, a query param or the client.
  # The URL is always on the issuer's host over https.
  #
  # Every failure raises Unavailable. Error messages never include the token.
  class UserProfileFetcher
    class Unavailable < StandardError; end

    PROFILE_PATH = "/oauth2/v2/user_profile"
    OPEN_TIMEOUT_SECONDS = 3
    READ_TIMEOUT_SECONDS = 3
    MAX_BODY_BYTES = 20_000

    class << self
      # One instance per process, built from KINDE_ISSUER_URL. Tests replace it.
      def default
        @default ||= new(issuer: ENV["KINDE_ISSUER_URL"])
      end

      attr_writer :default
    end

    # http_get: optional callable(URI, headers Hash) -> [status, body].
    def initialize(issuer:, http_get: nil)
      @uri = URI.parse("#{TokenVerifier.normalize_issuer!(issuer)}#{PROFILE_PATH}")
      @http_get = http_get || method(:net_http_get)
    end

    # Returns the profile as a Hash with String keys
    # (e.g. "id", "email", "email_verified", "given_name", "family_name").
    def call(access_token)
      raise Unavailable, "No access token" if access_token.blank?

      status, body = @http_get.call(@uri, { "Authorization" => "Bearer #{access_token}", "Accept" => "application/json" })
      raise Unavailable, "Unexpected HTTP status #{status} from #{@uri.host}" unless status == 200
      raise Unavailable, "Response from #{@uri.host} is too large" if body.to_s.bytesize > MAX_BODY_BYTES

      parsed = JSON.parse(body.to_s)
      raise Unavailable, "Response from #{@uri.host} is not a JSON object" unless parsed.is_a?(Hash)

      parsed
    rescue Unavailable
      raise
    rescue JSON::ParserError
      raise Unavailable, "Response from #{@uri.host} is not valid JSON"
    rescue StandardError => e
      raise Unavailable, "Could not fetch #{@uri.host} (#{e.class})"
    end

    private

    def net_http_get(uri, headers)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                          open_timeout: OPEN_TIMEOUT_SECONDS,
                                          read_timeout: READ_TIMEOUT_SECONDS) do |http|
        response = http.request(Net::HTTP::Get.new(uri, headers))
        [response.code.to_i, response.body]
      end
    end
  end
end
