# CORS (plan S3): browsers only. The native app doesn't use CORS; this matters
# for the Expo web build and any future web client.
#
# Allowed origins come from CORS_ORIGINS (comma-separated, exact origins such
# as https://app.example.com). Development defaults to the local Expo web
# ports. With no origins configured, no cross-origin browser access is
# allowed. A wildcard is refused: authentication uses bearer tokens, and the
# allowlist is the only browser-side control.
default_origins = Rails.env.development? ? "http://localhost:8081,http://localhost:19006" : ""
cors_origins = ENV.fetch("CORS_ORIGINS", default_origins).split(",").map(&:strip).reject(&:empty?)

if cors_origins.include?("*")
  raise "CORS_ORIGINS must list exact origins; '*' is not allowed"
end

if cors_origins.any?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins(*cors_origins)
      resource "/api/*",
        headers: %w[Authorization Content-Type Accept],
        methods: [:get, :post, :put, :patch, :delete, :options, :head],
        max_age: 600
    end
  end
end
