# frozen_string_literal: true

require "test_helper"

module Kinde
  class JwksFetcherTest < ActiveSupport::TestCase
    ISSUER = "https://budgetbuddy-test.kinde.com"
    DISCOVERY_URL = "#{ISSUER}/.well-known/openid-configuration"
    JWKS_URL = "#{ISSUER}/.well-known/jwks"
    JWKS_BODY = JSON.generate(keys: [{ kty: "RSA", kid: "k1", n: "abc", e: "AQAB" }])

    # Fake HTTP: maps URL strings to [status, body] or an exception; records requests.
    def http(responses)
      requested = []
      getter = lambda do |uri|
        requested << uri.to_s
        response = responses.fetch(uri.to_s) { [404, ""] }
        raise response if response.is_a?(Exception)

        response
      end
      [getter, requested]
    end

    def discovery(jwks_uri = JWKS_URL)
      [200, JSON.generate(issuer: ISSUER, jwks_uri: jwks_uri)]
    end

    test "fetches the JWKS via OIDC discovery" do
      getter, requested = http(DISCOVERY_URL => discovery, JWKS_URL => [200, JWKS_BODY])

      result = JwksFetcher.new(issuer: ISSUER, http_get: getter).call

      assert_equal "k1", result["keys"].first["kid"]
      assert_equal [DISCOVERY_URL, JWKS_URL], requested
    end

    test "rejects a jwks_uri on another host" do
      getter, requested = http(DISCOVERY_URL => discovery("https://attacker.example/jwks"))

      assert_raises(TokenVerifier::KeysUnavailable) { JwksFetcher.new(issuer: ISSUER, http_get: getter).call }
      assert_equal [DISCOVERY_URL], requested, "must not request the foreign jwks_uri"
    end

    test "rejects a non-https jwks_uri" do
      getter, = http(DISCOVERY_URL => discovery("http://budgetbuddy-test.kinde.com/.well-known/jwks"))
      assert_raises(TokenVerifier::KeysUnavailable) { JwksFetcher.new(issuer: ISSUER, http_get: getter).call }
    end

    test "rejects a discovery document without jwks_uri" do
      getter, = http(DISCOVERY_URL => [200, JSON.generate(issuer: ISSUER)])
      assert_raises(TokenVerifier::KeysUnavailable) { JwksFetcher.new(issuer: ISSUER, http_get: getter).call }
    end

    test "raises on non-200 responses" do
      getter, = http(DISCOVERY_URL => [500, "oops"])
      assert_raises(TokenVerifier::KeysUnavailable) { JwksFetcher.new(issuer: ISSUER, http_get: getter).call }
    end

    test "raises on invalid JSON" do
      getter, = http(DISCOVERY_URL => discovery, JWKS_URL => [200, "<html>"])
      assert_raises(TokenVerifier::KeysUnavailable) { JwksFetcher.new(issuer: ISSUER, http_get: getter).call }
    end

    test "raises when the JWKS has no keys array" do
      getter, = http(DISCOVERY_URL => discovery, JWKS_URL => [200, JSON.generate(keys: "nope")])
      assert_raises(TokenVerifier::KeysUnavailable) { JwksFetcher.new(issuer: ISSUER, http_get: getter).call }
    end

    test "raises on oversized responses" do
      getter, = http(DISCOVERY_URL => [200, "x" * (JwksFetcher::MAX_BODY_BYTES + 1)])
      assert_raises(TokenVerifier::KeysUnavailable) { JwksFetcher.new(issuer: ISSUER, http_get: getter).call }
    end

    test "wraps network errors" do
      getter, = http(DISCOVERY_URL => SocketError.new("getaddrinfo failed"))
      error = assert_raises(TokenVerifier::KeysUnavailable) { JwksFetcher.new(issuer: ISSUER, http_get: getter).call }
      assert_includes error.message, "SocketError"
    end

    test "rejects a non-https issuer at construction" do
      assert_raises(TokenVerifier::ConfigurationError) { JwksFetcher.new(issuer: "http://example.kinde.com") }
    end
  end
end
