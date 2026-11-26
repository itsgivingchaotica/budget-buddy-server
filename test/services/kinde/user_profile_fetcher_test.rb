# frozen_string_literal: true

require "test_helper"

module Kinde
  class UserProfileFetcherTest < ActiveSupport::TestCase
    ISSUER = "https://budgetbuddy-test.kinde.com"
    TOKEN = "header.payload.signature-secret-part"

    def fetcher_returning(status, body, calls: [])
      http_get = lambda do |uri, headers|
        calls << [uri, headers]
        raise body if body.is_a?(Exception)

        [status, body]
      end
      UserProfileFetcher.new(issuer: ISSUER, http_get: http_get)
    end

    test "calls the issuer's user_profile endpoint with the bearer token and returns the profile" do
      calls = []
      profile = fetcher_returning(200, { id: "kp_1", email: "a@example.com", email_verified: true }.to_json, calls: calls).call(TOKEN)

      assert_equal({ "id" => "kp_1", "email" => "a@example.com", "email_verified" => true }, profile)
      uri, headers = calls.first
      assert_equal "https://budgetbuddy-test.kinde.com/oauth2/v2/user_profile", uri.to_s
      assert_equal "Bearer #{TOKEN}", headers["Authorization"]
    end

    {
      "a non-200 status" => [401, "{}"],
      "invalid JSON" => [200, "not json"],
      "a JSON array" => [200, "[]"],
      "an oversized body" => [200, "x" * 25_000],
      "a network error" => [nil, SocketError.new("getaddrinfo failed")]
    }.each do |description, (status, body)|
      test "raises Unavailable for #{description}, without the token in the message" do
        error = assert_raises(UserProfileFetcher::Unavailable) { fetcher_returning(status, body).call(TOKEN) }
        assert_not_includes error.message, TOKEN
        assert_not_includes error.message, "signature-secret-part"
      end
    end

    test "raises Unavailable without a token and makes no request" do
      calls = []
      assert_raises(UserProfileFetcher::Unavailable) { fetcher_returning(200, "{}", calls: calls).call(nil) }
      assert_empty calls
    end

    test "requires an https issuer" do
      assert_raises(TokenVerifier::ConfigurationError) { UserProfileFetcher.new(issuer: "http://insecure.example") }
    end
  end
end
