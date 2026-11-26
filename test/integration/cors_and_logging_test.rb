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
    filtered = filter.filter("authorization" => "Bearer abc", "access_token" => "abc", "category" => "ok")

    assert_equal "[FILTERED]", filtered["authorization"]
    assert_equal "[FILTERED]", filtered["access_token"]
    assert_equal "ok", filtered["category"]
  end

  # M2 ground rule: no financial or personal text in request logs.
  test "money, names, notes and descriptions are filtered; ids, dates and slugs are kept" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    params = { "name" => "Rent", "amount" => "1200", "target_amount" => "500", "starting_balance" => "10",
               "balance_after" => "9", "monthly_payment" => "200", "apr" => "22.9", "note" => "x", "description" => "COFFEE",
               "first_name" => "A", "email" => "a@example.com",
               "budgets" => [{ "category" => "groceries", "amount" => "400" }],
               "transaction" => { "description" => "COFFEE", "category" => "dining-out" },
               "id" => "3", "due_on" => "2026-11-23", "category" => "rent", "goal_type" => "purchase" }
    out = filter.filter(params)
    %w[name amount target_amount starting_balance balance_after monthly_payment apr note description first_name email budgets].each do |k|
      assert_equal "[FILTERED]", out[k], k
    end
    assert_equal "[FILTERED]", out["transaction"]["description"]
    assert_equal({ "id" => "3", "due_on" => "2026-11-23", "category" => "rent", "goal_type" => "purchase" },
                 out.slice("id", "due_on", "category", "goal_type"))
    assert_equal "dining-out", out["transaction"]["category"]
  end

  # Everything the app logs (requests, controllers, Active Record), at debug.
  def capture_log
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io).tap { |l| l.level = :debug }
    Rails.logger.broadcast_to(sink)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  test "the request log never contains the bearer token" do
    token = access_token
    log = capture_log do
      get api_v1_budgets_url, params: { authorization: "Bearer #{token}" }, headers: { "Authorization" => "Bearer #{token}" }
    end
    assert_includes log, "Processing by", "the capture saw the request"
    assert_not_includes log, token
  end

  test "request lines and parameters hide money, names and notes, in the body and the query string" do
    log = capture_log do
      put api_v1_category_budgets_url, params: { month: "2026-05", budgets: [{ category: "groceries", amount: "987.65" }] },
                                       headers: auth_headers, as: :json
      get api_v1_category_budgets_url(month: "2026-05", note: "SECRET-NOTE", amount: "123.45"), headers: auth_headers
    end
    assert_includes log, "Started GET", "the capture saw the request"
    %w[987.65 SECRET-NOTE 123.45].each { |secret| assert_not_includes log, secret }
    assert_includes log, "month=2026-05", "non-sensitive parameters stay readable"
  end

  test "SQL statements are not logged, so values written into the SQL text never are" do
    log = capture_log do
      User.where("lower(email) = ?", "secret-sql@example.invalid").first
      Account.where(name: "SECRET-ACCOUNT").update_all(purpose_note: "SECRET-NOTE")
      get api_v1_budgets_url, headers: auth_headers
    end
    assert_includes log, "Completed 200", "the capture saw the request"
    %w[secret-sql SECRET-ACCOUNT SECRET-NOTE SELECT UPDATE].each { |text| assert_not_includes log, text }
  end

  # A database error's message holds the whole failing row; a JSON parse
  # error quotes the request body. Only the class, constraint and place are logged.
  module RaiseOnIndex
    def index
      raise Thread.current[:raise_on_index] if Thread.current[:raise_on_index]

      super
    end
  end
  Api::V1::CategoryBudgetsController.prepend(RaiseOnIndex)

  def with_error_logging
    ApplicationController.reraise_unexpected_errors = false
    yield
  ensure
    ApplicationController.reraise_unexpected_errors = true
    Thread.current[:raise_on_index] = nil
  end

  test "unexpected errors log a safe description, never the message, and the client gets a bare status" do
    with_error_logging do
      error = begin
        Transaction.transaction(requires_new: true) { Transaction.connection.execute("SELECT 1/0") } # a real PG error with a cause
      rescue ActiveRecord::StatementInvalid => e
        e
      end
      leaky = ActiveRecord::StatementInvalid.new(
        %(PG::CheckViolation: ERROR:  new row for relation "obligations" violates check constraint "obligations_amount_check"\n) +
        "DETAIL:  Failing row contains (7, 1, SECRET-BILL, -1200.00)."
      )
      Thread.current[:raise_on_index] = leaky
      log = capture_log { get api_v1_category_budgets_url, headers: auth_headers }
      assert_response :internal_server_error
      assert_equal({ "error" => "server_error" }, response.parsed_body)
      assert_includes log, "[error] ActiveRecord::StatementInvalid constraint=obligations_amount_check"
      %w[SECRET-BILL 1200 DETAIL Failing].each { |text| assert_not_includes log, text }
      assert_equal "ActiveRecord::StatementInvalid (PG::DivisionByZero)", SafeError.describe(error)

      Thread.current[:raise_on_index] = ArgumentError.new(%(invalid value for BigDecimal(): "SECRET-INPUT"))
      log = capture_log { get api_v1_category_budgets_url, headers: auth_headers }
      assert_response :internal_server_error
      assert_not_includes log, "SECRET-INPUT"
    end
  end

  test "a malformed JSON body is a 400 whose log never quotes the body" do
    Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 1)
    with_error_logging do
      put api_v1_category_budgets_url, params: { month: "2026-05", budgets: [{ category: "groceries", amount: "1" }] },
                                       headers: auth_headers, as: :json
      assert_response :success, "well-formed JSON still gets through"
      log = capture_log do
        put api_v1_category_budgets_url, params: '{"budgets": [{"amount": "SECRET-555"',
                                         headers: auth_headers.merge("Content-Type" => "application/json")
      end
      assert_response :bad_request
      assert_equal({ "error" => "bad_request" }, response.parsed_body)
      assert_includes log, "[error] malformed JSON request body (PUT /api/v1/category_budgets)"
      assert_not_includes log, "SECRET-555"
    end
  end

  test "Claude clients are built with tracing off, so no prompt or answer reaches a trace" do
    assert_equal false, AnthropicClient.sdk_options[:open_telemetry]
  end
end
