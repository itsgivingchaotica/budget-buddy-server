require "test_helper"

# W1: GET /outlook/week, the SPEC_LEFT_TO_SPEND §9 shape (money as strings).
class OutlookTest < ActionDispatch::IntegrationTest
  test "the §9 response shape for worked example 1" do
    groceries = Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 1)
    rent = Category.create!(name: "Rent", slug: "rent", kind: "spending", fixed_variable: "fixed", active: true, position: 2)
    users(:one).category_budgets.create!(category: groceries, amount: "640", effective_from: Date.new(2026, 11, 1))
    accounts(:one_checking).transactions.create!(posted_on: Date.new(2026, 11, 20), amount: "-85.60", description: "GROCER",
                                                 category: groceries, categorization_source: "rule")
    ob = users(:one).obligations.create!(name: "Rent", amount: "1200", category: rent, first_due_on: Date.new(2026, 1, 23), recurrence: "monthly")
    travel_to Time.utc(2026, 11, 22, 12) do
      get api_v1_outlook_week_url, headers: auth_headers, as: :json
    end
    assert_response :success
    body = response.parsed_body
    assert_equal ["ok", "2026-11-22", { "start" => "2026-11-16", "end" => "2026-11-22" }, "2026-11-20"],
                 body.values_at("state", "today", "week", "data_through")
    assert_equal({ "allowance" => "149.33", "spent" => "85.60", "left" => "63.73", "uncategorized_spent" => "0.00", "uncategorized_count" => 0,
                   "by_category" => [{ "category" => "groceries", "name" => "Groceries", "allowance" => "149.33", "spent" => "85.60", "left" => "63.73" }] },
                 body["left_to_spend"])
    assert_equal({ "window" => { "start" => "2026-11-22", "end" => "2026-11-28" },
                   "items" => [{ "obligation_id" => ob.id, "name" => "Rent", "amount" => "1200.00", "due_on" => "2026-11-23",
                                 "paid" => false, "paid_on" => nil, "overdue" => false }] }, body["bills_due"])
    assert_equal [], body["goal_contributions"]
    assert_includes body["assumptions"], "Based on transactions imported through 2026-11-20."
  end

  test "a new user with nothing yet: no_plan, zeros" do
    get api_v1_outlook_week_url, headers: auth_headers, as: :json
    assert_response :success
    assert_equal ["no_plan", "0.00", nil], [response.parsed_body["state"], response.parsed_body["left_to_spend"]["left"], nil]
  end

  test "money strings never show a negative zero" do
    formatter = Class.new { include MoneyJson; public :money }.new
    assert_equal ["0.00", "0.00", "-0.01", "12.50"], [BigDecimal("-0"), BigDecimal("-0.001"), BigDecimal("-0.005"), BigDecimal("12.5")].map { |v| formatter.money(v) }
  end
end
