require "test_helper"

# AN2 (analytics API) and the change-a-budget context (SCREENS_PLAN §3.1):
# shapes, validation, the caller's data only. Figures are AN1's
# (test/services/spending_analytics_test.rb).
class AnalyticsTest < ActionDispatch::IntegrationTest
  include SpendingScenario

  setup do
    build_spending_scenario
    travel_to NOW
  end

  teardown { travel_back }

  def call(url)
    get url, headers: auth_headers, as: :json
    response.parsed_body
  end

  test "GET /analytics/summary: money as strings, previous period, coverage" do
    body = call(api_v1_analytics_summary_url(from: "2026-11-01", to: "2026-11-26"))
    assert_response :success
    assert_equal ["1415.00", "3001.00", "18.00", 10], body.values_at("total_spent", "total_income", "uncategorized", "transaction_count")
    assert_equal({ "category" => "rent", "name" => "Rent", "spent" => "1212.00" }, body["categories"].first)
    assert_equal({ "amount" => "995.00", "percent" => "236.90" }, body["change"])
    assert_equal ["2026-10-06", "420.00"], body["previous"].values_at("from", "total_spent")
    assert_equal ["2026-08-01", "2026-11-20"], body.values_at("data_from", "data_through")
    assert_equal "40.00", call(api_v1_analytics_summary_url(from: "2026-11-01", to: "2026-11-26", category: "dining-out"))["total_spent"]
  end

  test "zero amounts are never \"-0.00\"" do
    body = call(api_v1_analytics_summary_url(from: "2026-10-01", to: "2026-10-31", category: "dining-out"))
    assert_equal "0.00", body["uncategorized"]
    assert_equal "0.00", call(api_v1_analytics_summary_url(from: "2026-07-01", to: "2026-07-31"))["total_spent"]
  end

  test "summary validation: dates, order, at most 366 days, known category" do
    [{ from: "2026-11-01" }, { from: "Nov 1", to: "2026-11-26" }, { from: "2026-11-26", to: "2026-11-01" },
     { from: "2025-10-31", to: "2026-11-01" }].each do |params| # the last: 367 days
      call(api_v1_analytics_summary_url(**params))
      assert_response :unprocessable_entity, params.inspect
    end
    call(api_v1_analytics_summary_url(from: "2025-11-01", to: "2026-11-01"))
    assert_response :success, "366 days, both ends counted"
    call(api_v1_analytics_summary_url(from: "2026-11-01", to: "2026-11-26", category: "no-such"))
    assert_equal ["invalid_reference", "category"], response.parsed_body.values_at("error", "field")
  end

  test "GET /analytics/budget_vs_actual: this month by default, any month by param" do
    body = call(api_v1_analytics_budget_vs_actual_url)
    assert_response :success
    assert_equal ["2026-11", true, "18.00", "2026-11-20"], body.values_at("month", "plan_exists", "uncategorized", "data_through")
    assert_equal({ "category" => "dining-out", "name" => "Dining Out", "budget" => "35.00", "spent" => "40.00", "remaining" => "-5.00", "status" => "over" },
                 body["categories"][1])
    assert_equal({ "budget" => "165.00", "spent" => "160.00", "remaining" => "5.00", "everyday_spent" => "203.00" }, body["totals"])
    assert_equal "420.00", call(api_v1_analytics_budget_vs_actual_url(month: "2026-10"))["categories"].first["spent"]
    call(api_v1_analytics_budget_vs_actual_url(month: "October"))
    assert_equal "month", response.parsed_body["field"]
  end

  test "GET /category_budgets/:slug/context: this month's budget by default, or the amount being edited" do
    body = call(context_api_v1_category_budget_url("groceries"))
    assert_response :success
    assert_equal({ "category" => "groceries", "name" => "Groceries", "month" => "2026-11", "amount" => "130.00", "weekly_equivalent" => "30.00",
                   "average_last_3_months" => "400.00", "months_averaged" => 3, "spent_this_month" => "120.00" }, body)
    assert_equal "92.00", call(context_api_v1_category_budget_url("groceries", amount: "400"))["weekly_equivalent"]
    body = call(context_api_v1_category_budget_url("personal-care"))
    assert_equal [nil, nil, "25.00"], body.values_at("amount", "weekly_equivalent", "spent_this_month"), "no budget yet"
  end

  test "context refuses fixed and unknown categories and bad amounts" do
    call(context_api_v1_category_budget_url("rent"))
    assert_equal ["not_flexible", "category"], response.parsed_body.values_at("error", "field")
    call(context_api_v1_category_budget_url("nope"))
    assert_response :unprocessable_entity
    %w[-1 lots 99999999999].each do |amount|
      call(context_api_v1_category_budget_url("groceries", amount:))
      assert_equal "amount", response.parsed_body["field"], amount
    end
  end

  test "another user sees only their own figures" do
    get api_v1_analytics_summary_url(from: "2026-11-01", to: "2026-11-26"), headers: auth_headers("sub" => users(:two).kinde_id), as: :json
    assert_response :success
    assert_equal "0.00", response.parsed_body["total_spent"]
  end
end
