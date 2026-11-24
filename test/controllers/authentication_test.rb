# frozen_string_literal: true

require "test_helper"

# S1b: every api/v1 endpoint requires a valid Kinde access token.
class AuthenticationTest < ActionDispatch::IntegrationTest
  # One read endpoint per controller, plus the two custom collection routes.
  ENDPOINTS = {
    "budgets#index" => -> { api_v1_budgets_url },
    "entries#index" => -> { api_v1_entries_url },
    "entries#entries_by_budget_with_default_categories" => -> { entries_by_budget_with_default_categories_api_v1_entries_url },
    "tags#index" => -> { api_v1_tags_url },
    "tags#default_tags" => -> { default_tags_api_v1_tags_url },
    "users#index" => -> { api_v1_users_url },
    "users#show_by_email" => -> { show_by_email_api_v1_users_url(email: "someone@example.com") },
    "categories#index" => -> { api_v1_categories_url },
    "categories#default" => -> { default_api_v1_categories_url }
  }.freeze

  def assert_unauthorized
    assert_response :unauthorized
    assert_equal({ "error" => "unauthorized" }, response.parsed_body)
    assert_equal 'Bearer realm="budget-buddy"', response.headers["WWW-Authenticate"]
  end

  def with_captured_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  # --- every endpoint ---------------------------------------------------------

  ENDPOINTS.each do |name, url|
    test "#{name} rejects a request without a token" do
      get instance_exec(&url), as: :json
      assert_unauthorized
    end
  end

  test "write endpoints reject a request without a token and change nothing" do
    budget = budgets(:one)
    assert_no_difference("Budget.count") do
      post api_v1_budgets_url, params: { budget: { name: "x", user_id: budget.user_id } }, as: :json
    end
    assert_unauthorized

    patch api_v1_budget_url(budget), params: { budget: { name: "changed" } }, as: :json
    assert_unauthorized
    assert_not_equal "changed", budget.reload.name

    assert_no_difference("Budget.count") { delete api_v1_budget_url(budget), as: :json }
    assert_unauthorized
  end

  # --- token problems -> 401 --------------------------------------------------

  {
    "an expired token" => -> { { "exp" => Time.now.to_i - 3600 } },
    "a token for another audience" => -> { { "aud" => ["https://some-other-api.example"] } },
    "a token without an audience" => -> { { "aud" => nil } },
    "a token from another issuer" => -> { { "iss" => "https://evil.kinde.com" } },
    "a token without a subject" => -> { { "sub" => nil } }
  }.each do |description, claims|
    test "rejects #{description}" do
      get api_v1_budgets_url, headers: auth_headers(**instance_exec(&claims)), as: :json
      assert_unauthorized
    end
  end

  test "rejects a token signed with the wrong key" do
    get api_v1_budgets_url, headers: auth_headers(key: OTHER_KEY), as: :json
    assert_unauthorized
  end

  test "rejects a token with an unknown key id" do
    get api_v1_budgets_url, headers: auth_headers(kid: "not-a-kinde-key"), as: :json
    assert_unauthorized
  end

  test "rejects garbage, an empty bearer value and other schemes" do
    ["Bearer not-a-jwt", "Bearer ", "Basic #{Base64.strict_encode64('user:pass')}", access_token].each do |value|
      get api_v1_budgets_url, headers: { "Authorization" => value }, as: :json
      assert_unauthorized
    end
  end

  test "accepts the scheme case-insensitively" do
    get api_v1_budgets_url, headers: { "Authorization" => "bearer #{access_token}" }, as: :json
    assert_response :success
  end

  # --- success, availability, public routes ---------------------------------

  test "accepts a valid token" do
    get api_v1_budgets_url, headers: auth_headers, as: :json
    assert_response :success
  end

  test "returns 503 when Kinde's keys can't be fetched" do
    failing = -> { raise Kinde::TokenVerifier::KeysUnavailable, "down" }
    Authenticatable.verifier = AuthTestHelper.build_verifier(fetcher: failing)

    get api_v1_budgets_url, headers: auth_headers, as: :json

    assert_response :service_unavailable
    assert_equal({ "error" => "authentication_unavailable" }, response.parsed_body)
  ensure
    AuthTestHelper.install_verifier!
  end

  test "the health check stays public" do
    get rails_health_check_url
    assert_response :success
  end

  # --- logging --------------------------------------------------------------

  test "logs only the rejection reason, never the token" do
    token = access_token("aud" => ["https://some-other-api.example"])
    log = with_captured_log do
      get api_v1_budgets_url, headers: { "Authorization" => "Bearer #{token}" }, as: :json
    end

    assert_unauthorized
    assert_includes log, "[auth] rejected request: invalid_audience"
    assert_not_includes log, token
    assert_not_includes log, token.split(".").last # not even the signature part
  end

  # --- configuration ----------------------------------------------------------

  test "the controllers' verifier requires an audience" do
    Authenticatable.verifier = nil
    original = ENV.to_h.slice("KINDE_ISSUER_URL", "KINDE_AUDIENCE")
    ENV["KINDE_ISSUER_URL"] = AuthTestHelper::ISSUER
    ENV.delete("KINDE_AUDIENCE")

    assert_raises(Kinde::TokenVerifier::ConfigurationError) { Authenticatable.verifier }
  ensure
    %w[KINDE_ISSUER_URL KINDE_AUDIENCE].each { |k| original&.key?(k) ? ENV[k] = original[k] : ENV.delete(k) }
    AuthTestHelper.install_verifier!
  end

  private

  OTHER_KEY = AuthTestHelper::OTHER_KEY
end
