require "test_helper"
require "minitest/mock"

# ON1: GET /onboarding and PUT /onboarding/answers (SPEC_ONBOARDING_PLAN §4).
class OnboardingTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 11, 26, 12)

  setup do
    @income = Category.create!(name: "Income", slug: "income", kind: "income", active: true, position: 20)
    @rent = Category.create!(name: "Rent", slug: "rent", kind: "spending", fixed_variable: "fixed", active: true, position: 10)
    checking = accounts(:one_checking)
    %w[2026-10-16 2026-10-30 2026-11-13].each_with_index do |day, i|
      checking.transactions.create!(posted_on: Date.parse(day), amount: "2300", description: "PAYROLL #{i}", category: @income, categorization_source: "rule")
    end
    %w[2026-09-01 2026-10-01].each { |day| checking.transactions.create!(posted_on: Date.parse(day), amount: "-1850", description: "OAK RENT", category: @rent, categorization_source: "rule") }
    venmo = users(:one).accounts.create!(name: "Venmo", kind: "p2p", purpose: "side_income")
    %w[2026-08-10 2026-09-10 2026-10-10].each { |day| venmo.transactions.create!(posted_on: Date.parse(day), amount: "410", description: "PAYMENT FROM A CLIENT") }
    travel_to NOW
  end

  teardown { travel_back }

  def call(verb, url, params = nil)
    public_send(verb, url, params:, headers: auth_headers, as: :json)
    response.parsed_body
  end

  test "GET: step, facts and the five questions, prefilled and templated by Rails" do
    body = call(:get, api_v1_onboarding_url)
    assert_response :success
    assert_equal ["accounts", 1], body.values_at("step", "version")
    assert_equal ["biweekly", "2026-11-13", "2300.00", "2026-11-27"], body["facts"]["pay_pattern"].values_at("frequency", "last_pay_on", "typical_amount", "next_pay_on")
    assert_equal %w[pay side_income bills goals change_appetite], body["questions"].map { |q| q["id"] }
    q = body["questions"].index_by { |x| x["id"] }
    assert_equal "Looks like every 2 weeks, last on Fri, Nov 13.", q["pay"]["hint"]
    assert_equal "I see about $410 a month coming into Venmo. Is that income from your side job?", q["side_income"]["text"]
    assert_equal [{ "name" => "OAK RENT", "amount" => "1850.00", "day" => 1, "category" => "rent", "detected" => true }], q["bills"]["prefill"]
    assert_equal "trim", q["change_appetite"]["prefill"]
  end

  test "no side income → no question 2" do
    Transaction.where(account: users(:one).accounts.find_by!(name: "Venmo")).delete_all
    assert_equal %w[pay bills goals change_appetite], call(:get, api_v1_onboarding_url)["questions"].map { |q| q["id"] }
  end

  test "PUT saves partial answers, the typed profile fields and the step; GET resumes there" do
    body = call(:put, api_v1_onboarding_answers_url, { step: "interview", pay: { frequency: "biweekly", next_pay_on: "2026-11-27", typical_amount: "2300" } })
    assert_response :success
    assert_equal "interview", body["step"]
    profile = users(:one).financial_profile.reload
    assert_equal ["biweekly", Date.new(2026, 11, 27), BigDecimal("2300"), 1], [profile.pay_frequency, profile.next_pay_on, profile.typical_pay_amount, profile.answers_version]
    call(:put, api_v1_onboarding_answers_url, { side_income: "yes", change_appetite: "push",
                                                bills: [{ name: "Rent", amount: "1850", day: 1, category: "rent", detected: true }],
                                                goals: [{ kind: "emergency_fund", amount: "2000" }, { kind: "debt_payoff", name: "Card", balance: "1840", apr: "22.9", monthly_payment: "120" }] })
    assert_response :success
    again = call(:get, api_v1_onboarding_url)
    assert_equal "interview", again["step"], "resumes where it stopped"
    assert_equal ["yes", "push"], again["answers"].values_at("side_income", "change_appetite")
    assert_equal "push", profile.reload.change_appetite
    assert_equal [{ "kind" => "emergency_fund", "name" => "Emergency fund", "amount" => "2000.00", "date" => nil },
                  { "kind" => "debt_payoff", "name" => "Card", "balance" => "1840.00", "apr" => "22.90", "monthly_payment" => "120.00" }],
                 again["answers"]["goals"], "stored in the shape the app sends"
    assert_equal "biweekly", again["answers"]["pay"]["frequency"], "earlier answers kept"
  end

  test "invalid answers: 422 per question, and nothing is saved" do
    body = call(:put, api_v1_onboarding_answers_url, { change_appetite: "trim", pay: { frequency: "daily" }, side_income: "maybe",
                                                       bills: [{ name: "", amount: "0", day: 32, category: "groceries" }],
                                                       goals: [{ kind: "upcoming_payment", name: "Car", amount: "600" }, { kind: "lottery" }], step: "party" })
    assert_response :unprocessable_entity
    assert_equal %w[bills goals pay side_income step], body["errors"].keys.sort
    assert_equal 4, body["errors"]["bills"].size
    assert_includes body["errors"]["goals"].join, "Target date is required"
    assert_includes body["errors"]["goals"].join, "goal 2: kind must be one of"
    assert_nil users(:one).financial_profile&.reload&.change_appetite, "all or nothing"
  end

  test "too many bills or goals, and wrong shapes" do
    call(:put, api_v1_onboarding_answers_url, { bills: Array.new(21) { { name: "X", amount: "1", day: 1, category: "rent" } } })
    assert_includes response.parsed_body["errors"]["bills"].join, "at most 20"
    call(:put, api_v1_onboarding_answers_url, { goals: "lots", pay: "weekly" })
    assert_equal({ "goals" => ["must be a list"], "pay" => ["must be an object"] }, response.parsed_body["errors"])
  end

  test "facts use only the caller's data" do
    get api_v1_onboarding_url, headers: auth_headers("sub" => users(:two).kinde_id), as: :json
    assert_response :success
    assert_equal ["irregular", nil], response.parsed_body["facts"]["pay_pattern"].values_at("frequency", "last_pay_on")
    assert_equal %w[pay bills goals change_appetite], response.parsed_body["questions"].map { |q| q["id"] }
  end

  # --- ON2: follow-ups ----------------------------------------------------------------

  class FakeClient
    def initialize(data) = @data = data

    def structured(**)
      AnthropicClient::Result.new(data: @data, model: "claude-haiku-5-5", input_tokens: 1, output_tokens: 1, duration_ms: 1)
    end
  end

  test "POST /onboarding/follow_ups: no AI in tests (real client refused) → no follow-ups, no error" do
    call(:put, api_v1_onboarding_answers_url, { side_income: "yes" })
    body = call(:post, api_v1_onboarding_follow_ups_url)
    assert_response :success
    assert_equal({ "follow_ups" => [] }, body)
  end

  test "follow-ups: shown with Rails options, answers checked against them, and GET shows them on resume" do
    call(:put, api_v1_onboarding_answers_url, { side_income: "yes", goals: [{ kind: "emergency_fund", amount: "2000" }, { kind: "purchase", name: "Bike", amount: "400" }] })
    fake = FakeClient.new({ "follow_ups" => [{ "slot" => "side_income_use", "question" => "Where should your side income go?" },
                                             { "slot" => "goal_priority", "question" => "Which goal comes first?" }] })
    body = AnthropicClient.stub(:new, fake) { call(:post, api_v1_onboarding_follow_ups_url) }
    assert_equal ["side_income_use", "goal_priority"], body["follow_ups"].map { |f| f["slot"] }
    assert_equal %w[goals everyday both], body["follow_ups"].first["options"].map { |o| o["value"] }
    assert_equal ["Emergency fund", "Bike"], body["follow_ups"].last["goals"].map { |g| g["name"] }

    call(:put, api_v1_onboarding_answers_url, { follow_ups: { side_income_use: "lottery", goal_priority: [0, 0], irregular_income_floor: "100" } })
    assert_response :unprocessable_entity
    assert_equal 3, response.parsed_body["errors"]["follow_ups"].size, "bad option, bad order, a slot that wasn't asked"

    call(:put, api_v1_onboarding_answers_url, { follow_ups: { side_income_use: "both", goal_priority: [1, 0] } })
    assert_response :success
    again = call(:get, api_v1_onboarding_url)
    assert_equal({ "side_income_use" => "both", "goal_priority" => [1, 0] }, again["answers"]["follow_ups"])
    assert_equal ["side_income_use", "goal_priority"], again["follow_ups"].map { |f| f["slot"] }
    assert_not again["answers"].key?("follow_ups_asked"), "internal bookkeeping stays out of answers"
  end
end
