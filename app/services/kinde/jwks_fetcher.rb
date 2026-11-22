# frozen_string_literal: true

require "json"
require "net/http"

module Kinde
  # Fetches Kinde's JSON Web Key Set (JWKS) using OpenID Connect discovery:
  #   GET <issuer>/.well-known/openid-configuration  ->  jwks_uri
  #   GET <jwks_uri>                                  ->  { "keys" => [...] }
  #
  # The jwks_uri must be https and on the same host as the issuer, so a
  # tampered discovery document cannot point key fetching elsewhere.
  #
  # Every failure raises Kinde::TokenVerifier::KeysUnavailable (an
  # infrastructure problem, distinct from an invalid token).
  class JwksFetcher
    DISCOVERY_PATH = "/.well-known/openid-configuration"
    OPEN_TIMEOUT_SECONDS = 3
    READ_TIMEOUT_SECONDS = 3
    MAX_BODY_BYTES = 100_000

    # http_get: optional callable(URI) -> [status_code(Integer), body(String)].
    # Injected in tests; defaults to Net::HTTP.
    def initialize(issuer:, http_get: nil)
      @issuer = TokenVerifier.normalize_issuer!(issuer)
      @issuer_host = URI.parse(@issuer).host
      @http_get = http_get || method(:net_http_get)
    end

    # Returns the parsed JWKS Hash ({ "keys" => [ ... ] }).
    def call
      discovery = get_json(URI.parse("#{@issuer}#{DISCOVERY_PATH}"))
      jwks_uri = validated_jwks_uri(discovery["jwks_uri"])

      jwks = get_json(jwks_uri)
      unless jwks["keys"].is_a?(Array)
        raise TokenVerifier::KeysUnavailable, "JWKS response has no keys array"
      end

      jwks
    end

    private

    def validated_jwks_uri(value)
      raise TokenVerifier::KeysUnavailable, "Discovery document has no jwks_uri" unless value.is_a?(String)

      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTPS) && uri.host == @issuer_host
        raise TokenVerifier::KeysUnavailable, "jwks_uri must be https on the issuer host"
      end

      uri
    rescue URI::InvalidURIError
      raise TokenVerifier::KeysUnavailable, "jwks_uri is not a valid URI"
    end

    def get_json(uri)
      status, body = @http_get.call(uri)
      raise TokenVerifier::KeysUnavailable, "Unexpected HTTP status #{status} from #{uri.host}" unless status == 200
      raise TokenVerifier::KeysUnavailable, "Response from #{uri.host} is too large" if body.to_s.bytesize > MAX_BODY_BYTES

      parsed = JSON.parse(body.to_s)
      raise TokenVerifier::KeysUnavailable, "Response from #{uri.host} is not a JSON object" unless parsed.is_a?(Hash)

      parsed
    rescue TokenVerifier::KeysUnavailable
      raise
    rescue JSON::ParserError
      raise TokenVerifier::KeysUnavailable, "Response from #{uri.host} is not valid JSON"
    rescue StandardError => e
      # Network errors, timeouts, TLS failures, etc. Only the class name is
      # reported; nothing sensitive is involved in key fetching.
      raise TokenVerifier::KeysUnavailable, "Could not fetch #{uri.host} (#{e.class})"
    end

    def net_http_get(uri)
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT_SECONDS,
        read_timeout: READ_TIMEOUT_SECONDS
      ) do |http|
        response = http.request(Net::HTTP::Get.new(uri, "Accept" => "application/json"))
        [response.code.to_i, response.body]
      end
    end
  end
end
