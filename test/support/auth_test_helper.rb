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
