require "test_helper"

# ON2: SPEC_ONBOARDING_PLAN §5 and §9 automated 5 and 7, with a fake
# Claude client (no API calls). "Today" is Thu 2026-11-26 (UTC).
class Onboarding::FollowUpsTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 26, 12)

  # Records every request and answers with a fixed payload (or raises).
  class FakeClient
    attr_reader :calls

    def initialize(data = { "follow_ups" => [] }, raise_error: nil)
      @data = data
      @raise = raise_error
      @calls = []
    end

    def structured(**kwargs)
      @calls << kwargs
      raise @raise if @raise

      AnthropicClient::Result.new(data: @data, model: "claude-haiku-5-5", input_tokens: 10, output_tokens: 10, duration_ms: 1)
    end
  end

  setup do
    @user = users(:one)
    cat = ->(name, slug, kind, fv, pos) { Category.create!(name:, slug:, kind:, fixed_variable: fv, active: true, position: pos) }
    @dining = cat.("Dining Out", "dining-out", "spending", "variable", 1)
    @rent = cat.("Rent", "rent", "spending", "fixed", 10)
    @checking = accounts(:one_checking)
    @n = 0
    travel_to NOW
  end

  teardown { travel_back }

  def row(on, amount, category, description: nil)
    @n += 1
    @checking.transactions.create!(posted_on: Date.parse(on), amount:, description: description || "ROW #{@n}", category:, categorization_source: "rule")
  end

  # Each request loads the user fresh; reload so the service sees these answers.
  def answers(hash)
    FinancialProfile.find_or_create_by!(user: @user).update!(answers: hash)
    @user.reload
  end
  def follow_ups(client) = Onboarding::FollowUps.call(@user, client:, now: NOW)
  def eligible = Onboarding::FollowUps.new(@user, client: nil, now: NOW).eligible_slots.keys.sort

  test "eligibility follows the spec's rules" do
    answers({})
    assert_equal [], eligible
    answers("pay" => { "frequency" => "irregular" }, "side_income" => "yes", "change_appetite" => "keep",
            "goals" => [{ "kind" => "purchase", "name" => "Bike" }, { "kind" => "emergency_fund" }], "bills" => [])
    assert_equal %w[goal_priority irregular_income_floor side_income_use], eligible, "keep: no trim question; no rent spending: no bill question"
    row("2026-09-01", "-1850", @rent)
    assert_includes eligible, "bill_missing", "rent spending but no rent bill kept"
    answers("bills" => [{ "name" => "Rent", "category" => "rent" }])
    assert_not_includes eligible, "bill_missing"
  end

  test "biggest_trim_ok: the top category's usual is at least 120% of its lowest recent month" do
    # Dining: Aug 300, Sep 300, Oct 200 → usual (median) 300 ≥ 1.2 × 200 = 240.
    # Rows on Jul 1 and Nov 20 make Aug–Oct full months the data covers.
    { "2026-08-10" => "-300", "2026-09-10" => "-300", "2026-10-10" => "-200" }.each { |d, a| row(d, a, @dining) }
    row("2026-07-01", "-1", @rent)
    row("2026-11-20", "-1", @rent)
    answers("change_appetite" => "trim")
    slots = Onboarding::FollowUps.new(@user, client: nil, now: NOW).eligible_slots
    assert_equal({ category: { slug: "dining-out", name: "Dining Out" } }, slots["biggest_trim_ok"])
    answers("change_appetite" => "keep")
    assert_not_includes eligible, "biggest_trim_ok", "keep things as they are: never ask about trimming"
    answers("change_appetite" => "push")
    assert_includes eligible, "biggest_trim_ok"
    Transaction.where(description: "ROW 3").update_all(amount: -260) # Oct 260: usual 300 < 1.2 × 260 = 312
    assert_not_includes eligible, "biggest_trim_ok"
  end

  test "the model picks and words; Rails supplies the options; asked once and stored" do
    answers("side_income" => "yes", "goals" => [{ "kind" => "purchase", "name" => "Bike" }, { "kind" => "debt_payoff", "name" => "Card" }])
    client = FakeClient.new({ "follow_ups" => [{ "slot" => "side_income_use", "question" => "What should your side income go toward?" },
                                               { "slot" => "goal_priority", "question" => "Which goal matters most to you?" }] })
    result = follow_ups(client)
    assert_equal [{ slot: "side_income_use", question: "What should your side income go toward?", input: "choice",
                    options: [{ value: "goals", label: "Toward goals" }, { value: "everyday", label: "Everyday spending" }, { value: "both", label: "Both" }] },
                  { slot: "goal_priority", question: "Which goal matters most to you?", input: "order",
                    goals: [{ index: 0, name: "Bike" }, { index: 1, name: "Card" }] }], result
    assert_equal ["onboarding", :assistant, @user], client.calls.first.values_at(:feature, :use, :for_user)
    again = FakeClient.new
    assert_equal result, follow_ups(again)
    assert_empty again.calls, "stored: no second call"
  end

  test "Rails drops unknown, ineligible, duplicate, digit-bearing and long questions, and keeps at most 2" do
    data = { "follow_ups" => [
      { "slot" => "made_up", "question" => "Anything?" },
      { "slot" => "bill_missing", "question" => "Do you pay rent?" },                # not eligible
      { "slot" => "side_income_use", "question" => "Put $200 toward goals?" },       # digits
      { "slot" => "side_income_use", "question" => "x" * 121 },                      # too long
      { "slot" => "side_income_use", "question" => "Where should side income go?" },
      { "slot" => "side_income_use", "question" => "Again?" },                       # duplicate
      { "slot" => "irregular_income_floor", "question" => "What can you count on?" },
      { "slot" => "goal_priority", "question" => "Which goal first?" }               # a third valid one
    ] }
    eligible = %w[side_income_use irregular_income_floor goal_priority]
    assert_equal [{ "slot" => "side_income_use", "question" => "Where should side income go?" },
                  { "slot" => "irregular_income_floor", "question" => "What can you count on?" }],
                 Onboarding::FollowUps.validate(data, eligible)
    assert_equal [], Onboarding::FollowUps.validate("nonsense", eligible)
  end

  test "any failure (refusal, outage, the AI cap) gives no follow-ups now, isn't stored, and is retried next time" do
    [AnthropicClient::Refused.new("no"), AnthropicClient::Unavailable.new("down"), AiBudget::Exceeded.new("cap")].each do |error|
      answers("side_income" => "yes")
      assert_equal [], follow_ups(FakeClient.new(raise_error: error)), error.class.name
      assert_nil @user.reload.financial_profile.answers["follow_ups_asked"], "a failure isn't stored"
    end
    later = FakeClient.new({ "follow_ups" => [{ "slot" => "side_income_use", "question" => "Where should it go?" }] })
    assert_equal ["side_income_use"], follow_ups(later).map { |f| f[:slot] }
    assert_equal 1, later.calls.size, "tried again after the failures"
  end

  test "a successful call that chooses none is stored, so it isn't asked again" do
    answers("side_income" => "yes")
    assert_equal [], follow_ups(FakeClient.new({ "follow_ups" => [] }))
    assert_equal [], @user.reload.financial_profile.answers["follow_ups_asked"]
    again = FakeClient.new
    follow_ups(again)
    assert_empty again.calls
  end

  test "nothing eligible: no model call, nothing stored" do
    answers("change_appetite" => "keep")
    client = FakeClient.new
    assert_equal [], follow_ups(client)
    assert_empty client.calls
    assert_nil @user.reload.financial_profile.answers["follow_ups_asked"]
  end

  test "if earlier answers change, only still-eligible stored follow-ups are shown" do
    answers("side_income" => "yes", "pay" => { "frequency" => "irregular" })
    follow_ups(FakeClient.new({ "follow_ups" => [{ "slot" => "side_income_use", "question" => "Where should it go?" },
                                                  { "slot" => "irregular_income_floor", "question" => "What can you count on?" }] }))
    profile = @user.reload.financial_profile
    answers(profile.answers.merge("side_income" => "no"))
    assert_equal ["irregular_income_floor"], follow_ups(FakeClient.new).map { |f| f[:slot] }
  end

  test "request capture: no merchant names, descriptions, account names, goal names, amounts or dates reach the model" do
    row("2026-09-01", "-1850", @rent, description: "OAK PROPERTY MANAGEMENT RENT")
    { "2026-08-10" => "-300", "2026-09-10" => "-300", "2026-10-10" => "-200" }.each { |d, a| row(d, a, @dining, description: "HARBOR BEAN CAFE") }
    row("2026-07-01", "-1", @rent, description: "OAK PROPERTY MANAGEMENT RENT")
    row("2026-11-20", "-1", @rent, description: "OAK PROPERTY MANAGEMENT RENT")
    answers("pay" => { "frequency" => "biweekly", "next_pay_on" => "2026-11-27", "typical_amount" => "2315.22" }, "side_income" => "yes",
            "change_appetite" => "trim", "bills" => [{ "name" => "VERIZON WIRELESS", "amount" => "65.00", "day" => 12, "category" => "utilities" }],
            "goals" => [{ "kind" => "purchase", "name" => "Trip to Lisbon", "amount" => "3000.00" }, { "kind" => "emergency_fund", "amount" => "2000.00" }])
    client = FakeClient.new
    follow_ups(client)
    sent = client.calls.first.values_at(:system, :user).join("\n")
    ["OAK PROPERTY", "HARBOR BEAN", "VERIZON", accounts(:one_checking).name, "Lisbon", "2315", "3000", "2000", "1850", "2026-11-27"].each do |secret|
      assert_not_includes sent, secret
    end
    assert_includes sent, "Dining Out", "category names are allowed (category level)"
    assert_includes sent, "biweekly"
  end
end
