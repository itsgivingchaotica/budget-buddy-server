# frozen_string_literal: true

module Kinde
  # Verifies Kinde-issued access tokens (JWTs) and returns their claims.
  #
  #   verifier = Kinde::TokenVerifier.from_env(require_audience: true)
  #   claims   = verifier.verify(raw_jwt)   # => { "sub" => "kp_...", ... }
  #
  # Checks: RS256 signature against Kinde's published keys (selected by `kid`),
  # `iss`, `exp` and `nbf` (with leeway), required `sub`/`exp`/`iss` claims,
  # and `aud` when an audience is configured.
  #
  # Errors:
  #   InvalidToken       - the token must be rejected (HTTP 401). `#reason` is a
  #                        Symbol safe to log; the token itself is never included.
  #   KeysUnavailable    - Kinde's keys could not be obtained (HTTP 503).
  #   ConfigurationError - missing/invalid issuer or required audience.
  #
  # Not yet wired into any controller (plan task S1b).
  class TokenVerifier
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class KeysUnavailable < Error; end

    class InvalidToken < Error
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super("Invalid access token (#{reason})")
      end
    end

    ALGORITHM = "RS256"
    REQUIRED_CLAIMS = %w[sub exp iss].freeze
    DEFAULT_LEEWAY_SECONDS = 30
    KEYS_TTL_SECONDS = 3600            # refresh cached keys hourly
    MAX_STALE_KEYS_SECONDS = 86_400    # never trust cached keys older than 24h
    MIN_RSA_KEY_BITS = 2048
    UNKNOWN_KID_REFRESH_SECONDS = 60   # at most one forced refresh per minute
    FAILED_FETCH_BACKOFF_SECONDS = 10  # fail fast while Kinde is unreachable
    MAX_TOKEN_BYTES = 8192

    # Returns the issuer as an https URL string without a trailing slash.
    def self.normalize_issuer!(issuer)
      value = issuer.to_s.strip.chomp("/")
      raise ConfigurationError, "Kinde issuer URL is not configured" if value.empty?

      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.path.empty? && uri.query.nil?
        raise ConfigurationError, "Kinde issuer URL must be an https origin, e.g. https://example.kinde.com"
      end

      value
    rescue URI::InvalidURIError
      raise ConfigurationError, "Kinde issuer URL is not a valid URI"
    end

    # Builds a verifier from KINDE_ISSUER_URL and KINDE_AUDIENCE.
    # S1b will call this with require_audience: true.
    def self.from_env(require_audience: false, **options)
      new(
        issuer: ENV["KINDE_ISSUER_URL"],
        audience: ENV["KINDE_AUDIENCE"],
        require_audience: require_audience,
        **options
      )
    end

    attr_reader :issuer, :audience

    # jwks_fetcher: callable returning a JWKS Hash ({ "keys" => [...] });
    #               defaults to Kinde::JwksFetcher (OIDC discovery over https).
    # clock:        callable returning monotonic seconds; injectable for tests.
    def initialize(issuer:, audience: nil, require_audience: false,
                   leeway: DEFAULT_LEEWAY_SECONDS, jwks_fetcher: nil,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @issuer = self.class.normalize_issuer!(issuer)
      @audience = audience.is_a?(String) ? audience.strip.presence : audience.presence
      if require_audience && @audience.nil?
        raise ConfigurationError, "KINDE_AUDIENCE must be set to verify Kinde access tokens"
      end

      @leeway = leeway
      @jwks_fetcher = jwks_fetcher || JwksFetcher.new(issuer: @issuer)
      @clock = clock
      @mutex = Mutex.new
      @keys_by_kid = nil
      @keys_fetched_at = nil
      @last_failed_fetch_at = nil
    end

    # Returns the verified claims as a frozen Hash with String keys.
    def verify(token)
      check_format!(token)

      # The two-argument key finder runs after the algorithm check and before
      # signature verification; it also rejects non-object payloads.
      payload, _header = JWT.decode(token, nil, true, decode_options) do |header, unverified_payload|
        reject!(:malformed) unless unverified_payload.is_a?(Hash)
        verification_key_for(header)
      end
      payload.freeze
    rescue JWT::ExpiredSignature
      reject!(:expired)
    rescue JWT::ImmatureSignature
      reject!(:not_yet_valid)
    rescue JWT::InvalidIssuerError
      reject!(:invalid_issuer)
    rescue JWT::InvalidAudError
      reject!(:invalid_audience)
    rescue JWT::MissingRequiredClaim
      reject!(:missing_claim)
    rescue JWT::IncorrectAlgorithm
      reject!(:invalid_algorithm)
    rescue JWT::SignatureError
      reject!(:invalid_signature)
    rescue JWT::DecodeError
      reject!(:malformed)
    end

    private

    # Raised without the underlying JWT error as `cause`, so callers that log
    # the exception chain only ever see the reason code.
    def reject!(reason)
      raise InvalidToken.new(reason), cause: nil
    end

    def check_format!(token)
      reject!(:missing) if token.nil?
      reject!(:malformed) unless token.is_a?(String)
      reject!(:malformed) if token.bytesize > MAX_TOKEN_BYTES # before any other processing
      reject!(:missing) if token.strip.empty?
    end

    def decode_options
      {
        algorithms: [ALGORITHM],
        verify_expiration: true,
        verify_not_before: true,
        leeway: @leeway,
        verify_iss: true,
        iss: [@issuer, "#{@issuer}/"],
        verify_aud: !@audience.nil?,
        aud: @audience,
        required_claims: REQUIRED_CLAIMS
      }
    end

    # Called by JWT.decode after the algorithm check, before signature checks.
    def verification_key_for(header)
      kid = header["kid"]
      reject!(:missing_key_id) unless kid.is_a?(String) && !kid.empty?

      key = current_keys[kid] || keys_after_unknown_kid_refresh[kid]
      reject!(:unknown_key) unless key

      key
    end

    # Cached keys, refreshed when older than KEYS_TTL_SECONDS. If a refresh
    # fails, cached keys keep working only until they are MAX_STALE_KEYS_SECONDS
    # old; after that we fail closed (KeysUnavailable) so a key Kinde has
    # revoked cannot be trusted indefinitely while Kinde is unreachable.
    def current_keys
      @mutex.synchronize do
        if @keys_by_kid.nil?
          fetch_keys!
        elsif now - @keys_fetched_at > KEYS_TTL_SECONDS
          begin
            fetch_keys!
          rescue KeysUnavailable => e
            raise if now - @keys_fetched_at > MAX_STALE_KEYS_SECONDS

            log_warning("Kinde key refresh failed; using cached keys (#{e.message})")
          end
        end
        @keys_by_kid
      end
    end

    # A token signed with a key we don't know may mean Kinde rotated keys.
    # Refetch once, but no more often than UNKNOWN_KID_REFRESH_SECONDS.
    def keys_after_unknown_kid_refresh
      @mutex.synchronize do
        if now - @keys_fetched_at > UNKNOWN_KID_REFRESH_SECONDS
          begin
            fetch_keys!
          rescue KeysUnavailable => e
            # Keep the cached keys; the token is then rejected as :unknown_key.
            log_warning("Kinde key refresh for unknown kid failed (#{e.message})")
          end
        end
        @keys_by_kid
      end
    end

    # Must be called while holding @mutex.
    def fetch_keys!
      if @last_failed_fetch_at && now - @last_failed_fetch_at < FAILED_FETCH_BACKOFF_SECONDS
        raise KeysUnavailable, "Kinde keys unavailable (backing off after a failed fetch)"
      end

      keys = parse_keys(@jwks_fetcher.call)
      raise KeysUnavailable, "Kinde JWKS contains no usable RS256 signing keys" if keys.empty?

      @keys_by_kid = keys
      @keys_fetched_at = now
      @last_failed_fetch_at = nil
    rescue KeysUnavailable
      @last_failed_fetch_at = now
      raise
    end

    def parse_keys(jwks)
      Array(jwks.is_a?(Hash) ? jwks["keys"] : nil).each_with_object({}) do |jwk, keys|
        next unless jwk.is_a?(Hash)
        next unless jwk["kty"] == "RSA"
        next if jwk["use"].present? && jwk["use"] != "sig"
        next if jwk["alg"].present? && jwk["alg"] != ALGORITHM
        next unless jwk["kid"].is_a?(String) && !jwk["kid"].empty?

        key = JWT::JWK.import(jwk).verify_key
        next unless key.is_a?(OpenSSL::PKey::RSA) && key.n.num_bits >= MIN_RSA_KEY_BITS

        keys[jwk["kid"]] = key
      rescue JWT::DecodeError, OpenSSL::PKey::PKeyError, OpenSSL::ASN1::ASN1Error, ArgumentError, TypeError
        # JWT::DecodeError covers JWKError and Base64DecodeError. One malformed
        # key must not break verification with the remaining usable keys.
        next
      end
    end

    def now
      @clock.call
    end

    def log_warning(message)
      Rails.logger&.warn("[Kinde::TokenVerifier] #{message}")
    end
  end
end
