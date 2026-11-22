# frozen_string_literal: true

require "test_helper"

module Kinde
  class TokenVerifierTest < ActiveSupport::TestCase
    ISSUER = "https://budgetbuddy-test.kinde.com"
    AUDIENCE = "https://api.budgetbuddy.test"

    # Generated once per test run; never leaves the process.
    KEY_A = OpenSSL::PKey::RSA.generate(2048)
    KEY_B = OpenSSL::PKey::RSA.generate(2048)

    # Returns queued JWKS responses (or raises queued exceptions) and counts calls.
    class FakeFetcher
      attr_reader :calls

      def initialize(*responses)
        @responses = responses
        @calls = 0
      end

      def call
        @calls += 1
        response = @responses.length > 1 ? @responses.shift : @responses.first
        raise response if response.is_a?(Exception)

        response
      end
    end

    class FakeClock
      attr_accessor :now

      def initialize
        @now = 1_000.0
      end

      def advance(seconds)
        @now += seconds
      end

      def to_proc
        -> { now }
      end
    end

    setup do
      @clock = FakeClock.new
    end

    # --- helpers ------------------------------------------------------------

    def jwks(*pairs)
      keys = pairs.map { |key, kid| JWT::JWK.new(key, kid: kid).export }
      JSON.parse(JSON.generate(keys: keys)) # String keys, like a real HTTP response
    end

    def build_verifier(fetcher: FakeFetcher.new(jwks([KEY_A, "kid-a"])), audience: nil, **options)
      TokenVerifier.new(issuer: ISSUER, audience: audience, jwks_fetcher: fetcher, clock: @clock.to_proc, **options)
    end

    # Claim overrides are passed as string keys, e.g. token("aud" => [...]).
    # A nil value removes the claim. Ruby 3 routes string-keyed hashes to **claims.
    def token(key: KEY_A, kid: "kid-a", alg: "RS256", **claims)
      now = Time.now.to_i
      payload = { "iss" => ISSUER, "sub" => "kp_user_123", "iat" => now, "exp" => now + 300 }
                .merge(claims.transform_keys(&:to_s)).compact
      headers = kid ? { kid: kid } : {}
      JWT.encode(payload, key, alg, headers)
    end

    def assert_rejected(reason, verifier, raw_token)
      error = assert_raises(TokenVerifier::InvalidToken) { verifier.verify(raw_token) }
      assert_equal reason, error.reason
      assert_not_includes error.message, raw_token.to_s if raw_token.is_a?(String) && raw_token.length > 10
      error
    end

    # --- happy path -----------------------------------------------------------

    test "returns frozen claims for a valid token" do
      claims = build_verifier.verify(token)

      assert_equal "kp_user_123", claims["sub"]
      assert_equal ISSUER, claims["iss"]
      assert claims.frozen?
    end

    test "accepts an issuer claim with a trailing slash" do
      assert_equal "kp_user_123", build_verifier.verify(token("iss" => "#{ISSUER}/"))["sub"]
    end

    test "accepts a token expired within the leeway" do
      assert build_verifier.verify(token("exp" => Time.now.to_i - 10))
    end

    # --- time-based claims ----------------------------------------------------

    test "rejects an expired token" do
      assert_rejected :expired, build_verifier, token("exp" => Time.now.to_i - 120)
    end

    test "rejects a token that is not yet valid" do
      assert_rejected :not_yet_valid, build_verifier, token("nbf" => Time.now.to_i + 120)
    end

    # --- signature and algorithm ----------------------------------------------

    test "rejects a token signed by a different key with a known kid" do
      assert_rejected :invalid_signature, build_verifier, token(key: KEY_B, kid: "kid-a")
    end

    test "rejects alg none" do
      unsigned = JWT.encode({ "iss" => ISSUER, "sub" => "x", "exp" => Time.now.to_i + 60 }, nil, "none", { kid: "kid-a" })
      assert_rejected :invalid_algorithm, build_verifier, unsigned
    end

    test "rejects HS256 signed with the public key as the secret (algorithm confusion)" do
      fetcher = FakeFetcher.new(jwks([KEY_A, "kid-a"]))
      forged = JWT.encode({ "iss" => ISSUER, "sub" => "x", "exp" => Time.now.to_i + 60 },
                          KEY_A.public_key.to_pem, "HS256", { kid: "kid-a" })

      assert_rejected :invalid_algorithm, build_verifier(fetcher: fetcher), forged
      assert_equal 0, fetcher.calls, "algorithm must be rejected before any key fetch"
    end

    test "rejects a token without a kid header" do
      assert_rejected :missing_key_id, build_verifier, token(kid: nil)
    end

    # --- issuer and audience --------------------------------------------------

    test "rejects a token from another issuer" do
      assert_rejected :invalid_issuer, build_verifier, token("iss" => "https://evil.kinde.com")
    end

    test "accepts a matching audience given as an array claim" do
      verifier = build_verifier(audience: AUDIENCE)
      assert verifier.verify(token("aud" => [AUDIENCE, "other"]))
    end

    test "accepts a matching audience given as a string claim" do
      assert build_verifier(audience: AUDIENCE).verify(token("aud" => AUDIENCE))
    end

    test "rejects a mismatched audience" do
      assert_rejected :invalid_audience, build_verifier(audience: AUDIENCE), token("aud" => ["https://other.api"])
    end

    test "rejects an empty audience array when an audience is configured" do
      assert_rejected :invalid_audience, build_verifier(audience: AUDIENCE), token("aud" => [])
    end

    test "rejects a missing audience when an audience is configured" do
      assert_rejected :invalid_audience, build_verifier(audience: AUDIENCE), token
    end

    test "does not check audience when none is configured" do
      assert build_verifier.verify(token("aud" => ["https://anything"]))
    end

    # --- required claims and format -------------------------------------------

    test "rejects a token without sub" do
      assert_rejected :missing_claim, build_verifier, token("sub" => nil)
    end

    test "rejects a token without exp" do
      assert_rejected :missing_claim, build_verifier, token("exp" => nil)
    end

    test "rejects nil and blank tokens as missing" do
      verifier = build_verifier
      assert_rejected :missing, verifier, nil
      assert_rejected :missing, verifier, ""
      assert_rejected :missing, verifier, "   "
    end

    test "rejects garbage and non-string tokens as malformed" do
      verifier = build_verifier
      assert_rejected :malformed, verifier, "not-a-jwt"
      assert_rejected :malformed, verifier, "aaa.bbb.ccc"
      assert_rejected :malformed, verifier, 12_345
    end

    test "rejects oversized tokens without decoding" do
      fetcher = FakeFetcher.new(jwks([KEY_A, "kid-a"]))
      assert_rejected :malformed, build_verifier(fetcher: fetcher), "a" * (TokenVerifier::MAX_TOKEN_BYTES + 1)
      assert_equal 0, fetcher.calls
    end

    # --- key caching and rotation ---------------------------------------------

    test "caches keys between verifications" do
      fetcher = FakeFetcher.new(jwks([KEY_A, "kid-a"]))
      verifier = build_verifier(fetcher: fetcher)

      3.times { verifier.verify(token) }
      assert_equal 1, fetcher.calls
    end

    test "refreshes keys after the cache TTL" do
      fetcher = FakeFetcher.new(jwks([KEY_A, "kid-a"]))
      verifier = build_verifier(fetcher: fetcher)

      verifier.verify(token)
      @clock.advance(TokenVerifier::KEYS_TTL_SECONDS + 1)
      verifier.verify(token)

      assert_equal 2, fetcher.calls
    end

    test "keeps using cached keys when a TTL refresh fails" do
      fetcher = FakeFetcher.new(jwks([KEY_A, "kid-a"]), TokenVerifier::KeysUnavailable.new("down"))
      verifier = build_verifier(fetcher: fetcher)

      verifier.verify(token)
      @clock.advance(TokenVerifier::KEYS_TTL_SECONDS + 1)

      assert verifier.verify(token)
      assert_equal 2, fetcher.calls
    end

    test "refetches once for an unknown kid and accepts a rotated key" do
      fetcher = FakeFetcher.new(jwks([KEY_A, "kid-a"]), jwks([KEY_A, "kid-a"], [KEY_B, "kid-b"]))
      verifier = build_verifier(fetcher: fetcher)

      verifier.verify(token)
      @clock.advance(TokenVerifier::UNKNOWN_KID_REFRESH_SECONDS + 1)

      assert_equal "kp_user_123", verifier.verify(token(key: KEY_B, kid: "kid-b"))["sub"]
      assert_equal 2, fetcher.calls
    end

    test "rate-limits refetches for unknown kids" do
      fetcher = FakeFetcher.new(jwks([KEY_A, "kid-a"]))
      verifier = build_verifier(fetcher: fetcher)

      verifier.verify(token)
      # Within the refresh interval: no refetch.
      assert_rejected :unknown_key, verifier, token(key: KEY_B, kid: "kid-unknown")
      assert_equal 1, fetcher.calls

      # After the interval: exactly one refetch, still unknown.
      @clock.advance(TokenVerifier::UNKNOWN_KID_REFRESH_SECONDS + 1)
      assert_rejected :unknown_key, verifier, token(key: KEY_B, kid: "kid-unknown")
      assert_rejected :unknown_key, verifier, token(key: KEY_B, kid: "kid-unknown")
      assert_equal 2, fetcher.calls
    end

    test "rejects an unknown kid as invalid when the refetch fails" do
      fetcher = FakeFetcher.new(jwks([KEY_A, "kid-a"]), TokenVerifier::KeysUnavailable.new("down"))
      verifier = build_verifier(fetcher: fetcher)

      verifier.verify(token)
      @clock.advance(TokenVerifier::UNKNOWN_KID_REFRESH_SECONDS + 1)
      assert_rejected :unknown_key, verifier, token(key: KEY_B, kid: "kid-b")
    end

    test "ignores non-RSA, encryption and wrong-alg keys" do
      usable = JWT::JWK.new(KEY_A, kid: "kid-a").export
      rejected = [
        JWT::JWK.new(KEY_B, kid: "kid-enc").export.merge(use: "enc"),
        JWT::JWK.new(KEY_B, kid: "kid-rs512").export.merge(alg: "RS512"),
        { kty: "oct", kid: "kid-oct", k: "c2VjcmV0" },
        { kty: "RSA", kid: "kid-broken", n: "!!", e: "AQAB" }
      ]
      fetcher = FakeFetcher.new(JSON.parse(JSON.generate(keys: rejected + [usable])))
      verifier = build_verifier(fetcher: fetcher)

      assert verifier.verify(token)
      assert_rejected :unknown_key, verifier, token(key: KEY_B, kid: "kid-enc")
    end

    # --- security review hardening (2026-11-22) -------------------------------

    def signed_raw(payload_json, key: KEY_A, kid: "kid-a")
      b64 = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
      header = b64.call(JSON.generate(alg: "RS256", kid: kid, typ: "JWT"))
      body = b64.call(payload_json)
      "#{header}.#{body}.#{b64.call(key.sign('SHA256', "#{header}.#{body}"))}"
    end

    test "rejects validly signed tokens whose payload is not a JSON object" do
      verifier = build_verifier
      ['"just-a-string"', "[1,2,3]", "123", "null"].each do |payload_json|
        assert_rejected :malformed, verifier, signed_raw(payload_json)
      end
    end

    test "fails closed once cached keys exceed the maximum stale age" do
      fetcher = FakeFetcher.new(jwks([KEY_A, "kid-a"]), TokenVerifier::KeysUnavailable.new("down"))
      verifier = build_verifier(fetcher: fetcher)
      verifier.verify(token)

      @clock.advance(TokenVerifier::KEYS_TTL_SECONDS + 1)
      assert verifier.verify(token), "stale keys are still trusted within the maximum stale age"

      @clock.advance(TokenVerifier::MAX_STALE_KEYS_SECONDS)
      assert_raises(TokenVerifier::KeysUnavailable) { verifier.verify(token) }
    end

    test "ignores RSA keys shorter than 2048 bits" do
      weak = OpenSSL::PKey::RSA.generate(1024)
      fetcher = FakeFetcher.new(jwks([weak, "kid-weak"], [KEY_A, "kid-a"]))
      verifier = build_verifier(fetcher: fetcher)

      assert verifier.verify(token)
      # jwt 3.x refuses to sign with a short key, so build the token by hand.
      weak_payload = JSON.generate(iss: ISSUER, sub: "kp_user_123", exp: Time.now.to_i + 300)
      assert_rejected :unknown_key, verifier, signed_raw(weak_payload, key: weak, kid: "kid-weak")
    end

    test "InvalidToken does not chain the underlying JWT error" do
      error = assert_rejected :invalid_audience, build_verifier(audience: AUDIENCE), token("aud" => ["https://x"])
      assert_nil error.cause
    end

    test "strips whitespace around the configured audience" do
      assert_equal AUDIENCE, build_verifier(audience: "  #{AUDIENCE}  ").audience
    end

    # --- key availability -----------------------------------------------------

    test "raises KeysUnavailable when no keys can be fetched" do
      fetcher = FakeFetcher.new(TokenVerifier::KeysUnavailable.new("down"))
      assert_raises(TokenVerifier::KeysUnavailable) { build_verifier(fetcher: fetcher).verify(token) }
    end

    test "raises KeysUnavailable when the JWKS has no usable keys" do
      fetcher = FakeFetcher.new({ "keys" => [{ "kty" => "oct", "kid" => "x", "k" => "c2VjcmV0" }] })
      assert_raises(TokenVerifier::KeysUnavailable) { build_verifier(fetcher: fetcher).verify(token) }
    end

    test "backs off after a failed fetch" do
      fetcher = FakeFetcher.new(TokenVerifier::KeysUnavailable.new("down"), jwks([KEY_A, "kid-a"]))
      verifier = build_verifier(fetcher: fetcher)

      assert_raises(TokenVerifier::KeysUnavailable) { verifier.verify(token) }
      assert_raises(TokenVerifier::KeysUnavailable) { verifier.verify(token) }
      assert_equal 1, fetcher.calls, "no fetch during the backoff window"

      @clock.advance(TokenVerifier::FAILED_FETCH_BACKOFF_SECONDS + 1)
      assert verifier.verify(token)
      assert_equal 2, fetcher.calls
    end

    # --- configuration --------------------------------------------------------

    test "requires an https issuer origin" do
      [nil, "", "http://example.kinde.com", "https://example.kinde.com/path", "not a url"].each do |bad|
        assert_raises(TokenVerifier::ConfigurationError, "expected #{bad.inspect} to be rejected") do
          TokenVerifier.new(issuer: bad, jwks_fetcher: FakeFetcher.new({}))
        end
      end
    end

    test "normalizes a trailing slash on the configured issuer" do
      verifier = TokenVerifier.new(issuer: "#{ISSUER}/", jwks_fetcher: FakeFetcher.new({}))
      assert_equal ISSUER, verifier.issuer
    end

    test "require_audience raises when no audience is configured" do
      assert_raises(TokenVerifier::ConfigurationError) do
        TokenVerifier.new(issuer: ISSUER, audience: " ", require_audience: true, jwks_fetcher: FakeFetcher.new({}))
      end
    end

    test "from_env reads KINDE_ISSUER_URL and KINDE_AUDIENCE" do
      original = ENV.to_h.slice("KINDE_ISSUER_URL", "KINDE_AUDIENCE")
      ENV["KINDE_ISSUER_URL"] = ISSUER
      ENV["KINDE_AUDIENCE"] = AUDIENCE

      verifier = TokenVerifier.from_env(require_audience: true, jwks_fetcher: FakeFetcher.new({}))
      assert_equal ISSUER, verifier.issuer
      assert_equal AUDIENCE, verifier.audience
    ensure
      %w[KINDE_ISSUER_URL KINDE_AUDIENCE].each { |name| original.key?(name) ? ENV[name] = original[name] : ENV.delete(name) }
    end
  end
end
