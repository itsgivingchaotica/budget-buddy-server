# frozen_string_literal: true

require "test_helper"

# S3: no wildcard CORS, and credentials never reach the logs.
class CorsAndLoggingTest < ActionDispatch::IntegrationTest
  test "a browser preflight from an unlisted origin gets no CORS permission" do
    process :options, api_v1_budgets_url, headers: {
      "Origin" => "https://evil.example",
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "Authorization"
    }
    assert_nil response.headers["Access-Control-Allow-Origin"]
  end

  test "authorization values are filtered from logged parameters" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("authorization" => "Bearer abc", "access_token" => "abc", "name" => "ok")

    assert_equal "[FILTERED]", filtered["authorization"]
    assert_equal "[FILTERED]", filtered["access_token"]
    assert_equal "ok", filtered["name"]
  end

  test "the request log never contains the bearer token" do
    token = access_token
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    get api_v1_budgets_url, params: { authorization: "Bearer #{token}" }, headers: { "Authorization" => "Bearer #{token}" }
  ensure
    Rails.logger = original
    assert_not_includes io.string, token
  end
end
