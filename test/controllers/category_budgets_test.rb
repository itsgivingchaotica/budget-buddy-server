require "test_helper"

# DM-3 (category budgets): the endpoints.
class CategoryBudgetsTest < ActionDispatch::IntegrationTest
  setup do
    @groceries = Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 1)
    @dining = Category.create!(name: "Dining Out", slug: "dining-out", kind: "spending", fixed_variable: "variable", active: true, position: 2)
    @rent = Category.create!(name: "Rent", slug: "rent", kind: "spending", fixed_variable: "fixed", active: true, position: 3)
  end

  def call(verb, url, params = nil)
    public_send(verb, url, params:, headers: auth_headers, as: :json)
    response.parsed_body
  end

  test "GET lists every flexible category with the amount in effect that month" do
    users(:one).category_budgets.create!(category: @groceries, amount: 400, effective_from: Date.new(2026, 3, 1))
    body = call(:get, api_v1_category_budgets_url(month: "2026-04"))
    assert_response :success
    assert_equal "2026-04", body["month"]
    assert_equal "400.00", body["total"]
    assert_equal [{ "category" => "groceries", "name" => "Groceries", "amount" => "400.00", "effective_from" => "2026-03-01" },
                  { "category" => "dining-out", "name" => "Dining Out", "amount" => nil, "effective_from" => nil }],
                 body["budgets"]
  end

  test "a bad month is 422" do
    call(:get, api_v1_category_budgets_url(month: "April"))
    assert_response :unprocessable_entity
  end

  test "PUT /category_budgets sets several budgets from that month on, all or nothing" do
    body = call(:put, api_v1_category_budgets_url, { month: "2026-05", budgets: [{ category: "groceries", amount: "450.00" }, { category: "dining-out", amount: "120" }] })
    assert_response :success
    assert_equal "570.00", body["total"]
    assert_equal [Date.new(2026, 5, 1)], users(:one).category_budgets.distinct.pluck(:effective_from)

    assert_no_difference -> { CategoryBudget.count } do
      call(:put, api_v1_category_budgets_url, { month: "2026-06", budgets: [{ category: "groceries", amount: "1" }, { category: "rent", amount: "1500" }] })
    end
    assert_response :unprocessable_entity, "a fixed category refuses the whole request"
  end

  test "setting the same month again updates the row instead of adding one" do
    2.times { |i| call(:put, api_v1_category_budgets_url, { month: "2026-05", budgets: [{ category: "groceries", amount: "#{400 + i}" }] }) }
    assert_equal [BigDecimal("401")], users(:one).category_budgets.pluck(:amount)
  end

  test "PUT /category_budgets/:slug changes one budget from this month, in the user's time zone" do
    FinancialProfile.find_or_create_by!(user: users(:one)).update!(time_zone: "America/New_York")
    travel_to Time.utc(2026, 12, 1, 3, 0) do # still Nov 30 in New York
      body = call(:put, api_v1_category_budget_url("groceries"), { amount: "200.00" })
      assert_response :success
      assert_equal({ "category" => "groceries", "name" => "Groceries", "amount" => "200.00", "effective_from" => "2026-11-01" }, body)
    end
  end

  test "unknown, fixed or negative budgets are refused" do
    call(:put, api_v1_category_budget_url("no-such"), { amount: "1" })
    assert_response :unprocessable_entity
    assert_equal "invalid_reference", response.parsed_body["error"]
    call(:put, api_v1_category_budget_url("rent"), { amount: "1500" })
    assert_response :unprocessable_entity
    call(:put, api_v1_category_budget_url("groceries"), { amount: "-5" })
    assert_response :unprocessable_entity
    call(:put, api_v1_category_budget_url("groceries"), { amount: "lots" })
    assert_response :unprocessable_entity
    assert_equal 0, CategoryBudget.count
  end

  test "another user's budgets are never shown or changed" do
    users(:two).category_budgets.create!(category: @groceries, amount: 999, effective_from: Date.new(2026, 1, 1))
    assert_nil call(:get, api_v1_category_budgets_url(month: "2026-06"))["budgets"].first["amount"]
    call(:put, api_v1_category_budget_url("groceries"), { amount: "10" })
    assert_equal [BigDecimal("999")], users(:two).category_budgets.pluck(:amount)
  end
end
