require "test_helper"
require "minitest/mock"

# PL1 (plan drafting): the plan_proposals endpoints, SPEC_ONBOARDING_PLAN
# §6.4 and §7 (adjustments), D-032. No real Claude calls (fake client).
class PlanProposalsTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 11, 26, 12)

  class FakeClient
    def initialize(data) = @data = data

    def structured(**)
      AnthropicClient::Result.new(data: @data, model: "claude-haiku-5-5", input_tokens: 1, output_tokens: 1, duration_ms: 1)
    end
  end

  setup do
    AiRateLimit.reset!
    @user = users(:one)
    @dining = Category.create!(name: "Dining Out", slug: "dining-out", kind: "spending", fixed_variable: "variable", active: true, position: 1)
    @income = Category.create!(name: "Income", slug: "income", kind: "income", active: true, position: 20)
    checking = accounts(:one_checking)
    # Dining 290 a month Jul–Oct (keep 290, trim 260); income 2000 a month.
    %w[07 08 09 10].each_with_index do |m, i|
      checking.transactions.create!(posted_on: Date.parse("2026-#{m}-10"), amount: -290, description: "CAFE #{i}", category: @dining, categorization_source: "rule")
      checking.transactions.create!(posted_on: Date.parse("2026-#{m}-15"), amount: 2000, description: "PAY #{i}", category: @income, categorization_source: "rule")
    end
    checking.transactions.create!(posted_on: Date.parse("2026-07-01"), amount: -1, description: "START", category: @dining, categorization_source: "rule")
    checking.transactions.create!(posted_on: Date.parse("2026-11-20"), amount: -1, description: "END", category: @dining, categorization_source: "rule")
    FinancialProfile.find_or_create_by!(user: @user).update!(answers: {
      "pay" => { "frequency" => "monthly" }, "side_income" => "no", "change_appetite" => "trim",
      "bills" => [{ "name" => "Rent", "amount" => "1500.00", "day" => 1, "category" => "rent" }],
      "goals" => [{ "kind" => "purchase", "name" => "Bike", "amount" => "400.00", "date" => nil }]
    })
    Import.update_all(created_at: NOW - 1.day) # fixture imports are stamped with the real clock
    travel_to NOW
  end

  teardown { travel_back }

  def post_draft(data = { "intro" => "A gentle start.", "budgets" => [{ "category_slug" => "dining-out", "option" => "trim", "reason" => "A little less eating out." }], "goal_order" => [] })
    AnthropicClient.stub(:new, FakeClient.new(data)) { post api_v1_plan_proposals_url, headers: auth_headers, as: :json }
    response.parsed_body["plan_proposal"]
  end

  test "POST builds a draft with Rails figures; GET current returns it" do
    draft = post_draft
    assert_response :created
    assert_equal %w[draft model], draft.values_at("status", "source")
    assert_equal [["dining-out", "trim", "260.00", "290.00"]], draft["categories"].map { |c| c.values_at("category", "option", "amount", "usual") }
    # Income 2000; committed: rent 1500 (the undated Bike goal adds nothing) → room 500; everyday 260 → fits.
    assert_equal ["2000.00", "1500.00", "500.00", "260.00", true, false],
                 [draft["income"]["monthly"], draft["committed"]["total"], draft["room"], draft["everyday_total"], draft["fits"], draft["stale"]]

    get api_v1_plan_proposals_current_url, headers: auth_headers, as: :json
    assert_equal draft["id"], response.parsed_body["plan_proposal"]["id"]
  end

  test "PATCH adjusts the draft and Rails recomputes the fit line; bad changes → 422, nothing saved" do
    id = post_draft["id"]
    patch api_v1_plan_proposal_url(id), params: { budgets: [{ category: "dining-out", amount: "600" }], bills: [{ key: "bill_0", amount: "1450.00" }] },
                                        headers: auth_headers, as: :json
    assert_response :ok
    body = response.parsed_body["plan_proposal"]
    # Rent 1450 → room 550; dining 600 (custom) → over by 50.
    assert_equal [["custom", "600.00"], "550.00", false, "50.00"],
                 [body["categories"].first.values_at("option", "amount"), body["room"], body["fits"], body["gap"]]
    patch api_v1_plan_proposal_url(id), params: { budgets: [{ category: "dining-out", amount: "290" }] }, headers: auth_headers, as: :json
    assert_equal "keep", response.parsed_body["plan_proposal"]["categories"].first["option"], "an amount equal to an option is that option"

    before = PlanProposal.find(id).payload
    patch api_v1_plan_proposal_url(id), params: { budgets: [{ category: "dining-out", amount: "-5" }], goals: [{ key: "goal_0", amount: "0" }] },
                                        headers: auth_headers, as: :json
    assert_response :unprocessable_entity
    assert_equal %w[budgets goals], response.parsed_body["errors"].keys.sort
    assert_equal before, PlanProposal.find(id).payload, "all or nothing"
  end

  test "PATCH a stale or superseded draft is refused" do
    first = post_draft["id"]
    second = post_draft["id"]
    patch api_v1_plan_proposal_url(first), params: { budgets: [] }, headers: auth_headers, as: :json
    assert_response :conflict
    assert_equal "superseded", response.parsed_body["status"]

    travel_to NOW + 8.days
    patch api_v1_plan_proposal_url(second), params: { budgets: [] }, headers: auth_headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "stale", response.parsed_body["error"]
  end

  test "at most 5 drafts a day per user (429 with Retry-After)" do
    5.times { post_draft }
    post_draft
    assert_response :too_many_requests
    assert_equal "rate_limited", response.parsed_body["error"]
    assert response.headers["Retry-After"].to_i.positive?
  end

  test "a draft made before a newer import is stale" do
    id = post_draft["id"]
    travel_to NOW + 1.hour
    accounts(:one_checking).imports.create!(filename: "nov.csv", status: "completed")
    get api_v1_plan_proposals_current_url, headers: auth_headers, as: :json
    assert_equal [id, true], response.parsed_body["plan_proposal"].values_at("id", "stale")
  end

  test "no draft yet → current is null" do
    get api_v1_plan_proposals_current_url, headers: auth_headers, as: :json
    assert_response :ok
    assert_nil response.parsed_body["plan_proposal"]
  end
end
