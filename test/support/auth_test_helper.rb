# frozen_string_literal: true

# Signs test access tokens with a locally generated RSA key and installs a
# Kinde::TokenVerifier that reads that key from a fake JWKS fetcher, so
# request tests never touch the network.
module AuthTestHelper
  ISSUER = "https://budgetbuddy-test.kinde.com"
  AUDIENCE = "https://api.budgetbuddy.test"
  KID = "test-kid"

  # Generated once per test run; never leaves the process.
  SIGNING_KEY = OpenSSL::PKey::RSA.generate(2048)
  OTHER_KEY = OpenSSL::PKey::RSA.generate(2048)

  JWKS = JSON.parse(JSON.generate(keys: [JWT::JWK.new(SIGNING_KEY, kid: KID).export])).freeze

  def self.build_verifier(fetcher: -> { JWKS })
    Kinde::TokenVerifier.new(issuer: ISSUER, audience: AUDIENCE, require_audience: true, jwks_fetcher: fetcher)
  end

  def self.install_verifier!
    Authenticatable.verifier = build_verifier
  end

  # Stands in for Kinde's /oauth2/v2/user_profile. Records the tokens it was
  # called with; raises Unavailable when given an exception or nothing.
  class FakeProfileFetcher
    attr_reader :tokens

    def initialize(response = nil)
      @response = response
      @tokens = []
    end

    def call(access_token)
      @tokens << access_token
      raise Kinde::UserProfileFetcher::Unavailable, "no Kinde profile in tests" if @response.nil?
      raise @response if @response.is_a?(Exception)

      @response
    end

    def calls
      @tokens.size
    end
  end

  # By default no test may reach Kinde's profile endpoint.
  def self.install_profile_fetcher!(fetcher = FakeProfileFetcher.new)
    Kinde::UserProfileFetcher.default = fetcher
  end

  # Runs the block with a fake Kinde profile response; returns the fake.
  def with_kinde_profile(response)
    fake = FakeProfileFetcher.new(response)
    AuthTestHelper.install_profile_fetcher!(fake)
    yield fake
    fake
  ensure
    AuthTestHelper.install_profile_fetcher!
  end

  def kinde_profile(sub: "kp_test_user", email: "new.person@example.com", email_verified: true, **extra)
    { "id" => sub, "email" => email, "email_verified" => email_verified,
      "given_name" => "New", "family_name" => "Person" }.merge(extra.transform_keys(&:to_s)).compact
  end

  # Claim overrides use string keys; a nil value removes the claim.
  def access_token(key: SIGNING_KEY, kid: KID, **claims)
    now = Time.now.to_i
    payload = { "iss" => ISSUER, "aud" => [AUDIENCE], "sub" => "kp_test_user", "iat" => now, "exp" => now + 300 }
              .merge(claims.transform_keys(&:to_s)).compact
    JWT.encode(payload, key, "RS256", { kid: kid })
  end

  def auth_headers(**options)
    { "Authorization" => "Bearer #{access_token(**options)}" }
  end
end
