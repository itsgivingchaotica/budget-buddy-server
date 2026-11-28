require "test_helper"

# PL1 (plan drafting): SPEC_ONBOARDING_PLAN §6.3–6.4 and D-032, §9 automated
# 4 and 7, with a fake Claude client (no API calls). "Today" is Thu
# 2026-11-26 (UTC). Spending as in PlanFiguresTest: dining usual 290 (keep 290,
# trim 260, stretch 230), groceries 406 (keep 410, trim 365), entertainment 20
# (keep 20; stretch 15 for push), clothing 100 (keep 100, trim 90, stretch 80).
class PlanDrafterTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 26, 12)

  class FakeClient
    attr_reader :calls

    # `answers`: one per call (a Hash is the model's JSON; an exception is raised).
    def initialize(*answers)
      @answers = answers
      @calls = []
    end

    def structured(**kwargs)
      @calls << kwargs
      answer = @answers[[@calls.size - 1, @answers.size - 1].min]
      raise answer if answer.is_a?(Exception)

      AnthropicClient::Result.new(data: answer, model: "claude-haiku-5-5", input_tokens: 10, output_tokens: 10, duration_ms: 1)
    end
  end

  setup do
    @user = users(:one)
    cat = ->(name, slug, kind, fv, pos) { Category.create!(name:, slug:, kind:, fixed_variable: fv, active: true, position: pos) }
    @groceries = cat.("Groceries", "groceries", "spending", "variable", 1)
    @dining = cat.("Dining Out", "dining-out", "spending", "variable", 2)
    @fun = cat.("Entertainment", "entertainment", "spending", "variable", 3)
    @clothing = cat.("Clothing", "clothing", "spending", "variable", 4)
    @rent = cat.("Rent", "rent", "spending", "fixed", 10)
    @income = cat.("Income", "income", "income", nil, 20)
    @checking = accounts(:one_checking)
    @n = 0
    travel_to NOW
    { "07" => [260, 400], "08" => [300, 412], "09" => [310, 388], "10" => [280, 420] }.each do |m, (d, g)|
      row("2026-#{m}-10", -d, @dining, "HARBOR BEAN CAFE")
      row("2026-#{m}-12", -g, @groceries, "GREENLEAF MARKET")
      row("2026-#{m}-14", -20, @fun, "CINEMA PLAZA")
      row("2026-#{m}-16", -100, @clothing, "THREADS OUTLET")
      row("2026-#{m}-15", 4630, @income, "ACME PAYROLL")
    end
    row("2026-07-01", -1, @rent, "OAK PROPERTY MANAGEMENT")
    row("2026-11-20", -1, @rent, "OAK PROPERTY MANAGEMENT")
  end

  teardown { travel_back }

  def row(on, amount, category, description)
    @n += 1
    @checking.transactions.create!(posted_on: Date.parse(on), amount:, description: "#{description} #{@n}", category:, categorization_source: "rule")
  end

  def answers(hash)
    base = { "pay" => { "frequency" => "monthly" }, "side_income" => "no", "bills" => [], "goals" => [] }
    FinancialProfile.find_or_create_by!(user: @user).update!(answers: base.merge(hash))
    @user.reload
  end

  def draft(client) = PlanDrafter.call(@user, client:, now: NOW)
  def picks(proposal) = proposal.payload["categories"].to_h { |c| [c["category"], [c["option"], c["amount"]]] }

  def answer(budgets, intro: "Here's a gentle plan built from your spending.", goal_order: [])
    { "intro" => intro, "budgets" => budgets.map { |slug, option, reason| { "category_slug" => slug, "option" => option, "reason" => reason.to_s } },
      "goal_order" => goal_order }
  end

  GOOD = [["groceries", "keep", ""], ["dining-out", "trim", "Eating out a little less."], ["entertainment", "keep", ""],
          ["clothing", "trim", "A small cut here."]].freeze

  test "the model chooses; every amount comes from Rails' options; stored as the open draft" do
    answers("change_appetite" => "trim")
    client = FakeClient.new(answer(GOOD))
    proposal = draft(client)
    assert_equal %w[draft model claude-haiku-5-5], [proposal.status, proposal.source, proposal.model]
    assert_equal({ "groceries" => ["keep", "410.00"], "dining-out" => ["trim", "260.00"], "entertainment" => ["keep", "20.00"],
                   "clothing" => ["trim", "90.00"] }, picks(proposal))
    assert_equal "Eating out a little less.", proposal.payload["categories"].find { |c| c["category"] == "dining-out" }["reason"]
    # Income 4630 (median), nothing committed → room 4630; everyday 410 + 260 + 20 + 90 = 780 → fits.
    assert_equal ["4630.00", "780.00", true], [proposal.payload["room"], proposal.payload["everyday_total"], proposal.payload["fits"]]
    assert_equal 4, proposal.payload["months"]
    assert_equal ["plan", :assistant, @user], client.calls.first.values_at(:feature, :use, :for_user)
    assert_equal 1, client.calls.size

    second = draft(FakeClient.new(answer(GOOD)))
    assert_equal "superseded", proposal.reload.status, "a new draft replaces the open one"
    assert_equal [second.id], @user.plan_proposals.drafts.ids
  end

  test "Rails' checks: missing category, unknown option, digits, too long, extra keys, appetite limits (§6.3)" do
    candidates = PlanCandidates.call(answers("change_appetite" => "trim"), @user.financial_profile.answers)
    check = ->(data, appetite = "trim") { PlanDrafter.validate(data, candidates, [], appetite:).last }
    assert_empty check.(answer(GOOD))
    assert_includes check.(answer(GOOD.first(3))), "missing categories: clothing"
    assert_includes check.(answer(GOOD[0..2] + [["clothing", "stretch", "x"]])), "category clothing has no option stretch"
    assert_includes check.(answer(GOOD + [["made-up", "keep", ""]])), "unknown category made-up"
    assert_includes check.(answer(GOOD + [["clothing", "keep", ""]])), "category clothing appears more than once"
    assert_includes check.(answer(GOOD.map { |s, o, _| [s, o, ""] })), "category dining-out needs a reason for trim"
    assert_includes check.(answer(GOOD, intro: "Save $50 a week!")), "intro contains digits"
    assert_includes check.(answer(GOOD[0..2] + [["clothing", "trim", "Cut 10%"]])), "a reason contains digits"
    assert_includes check.(answer(GOOD, intro: "x" * 201)), "intro is longer than 200 characters"
    assert_includes check.(answer(GOOD[0..2] + [["clothing", "trim", "y" * 81]])), "a reason is longer than 80 characters"
    assert_includes check.(answer(GOOD).merge("amount" => 5)), "unknown keys: amount"
    four = [["groceries", "trim", "a"], ["dining-out", "trim", "b"], ["entertainment", "keep", ""], ["clothing", "trim", "c"]]
    assert_empty check.(answer(four)), "3 trims is the limit for small trims"
    push = PlanCandidates.call(answers("change_appetite" => "push"), @user.financial_profile.answers)
    stretchy = [["groceries", "trim", "a"], ["dining-out", "stretch", "b"], ["entertainment", "stretch", "c"], ["clothing", "trim", "d"]]
    assert_empty PlanDrafter.validate(answer(stretchy), push, [], appetite: "push").last, "push: any options, any count"
    assert_includes PlanDrafter.validate(answer(stretchy), push, [], appetite: "trim").last, "no stretch for small trims"
    five = { categories: %w[a b c d e].map { |s| { category: s, options: { "keep" => 50, "trim" => 45 } } } }
    trims = ->(n) { answer(%w[a b c d e].each_with_index.map { |s, i| [s, i < n ? "trim" : "keep", "A little less."] }) }
    assert_empty PlanDrafter.validate(trims.(3), five, [], appetite: "trim").last
    assert_includes PlanDrafter.validate(trims.(4), five, [], appetite: "trim").last, "at most 3 trims for small trims"
  end

  test "one retry with the problems listed, then the deterministic fallback (§6.3)" do
    answers("change_appetite" => "trim")
    bad = answer(GOOD.first(3))
    retried = FakeClient.new(bad, answer(GOOD))
    assert_equal "model", draft(retried).source
    assert_equal 2, retried.calls.size
    assert_includes retried.calls.last[:user], "missing categories: clothing"

    twice = FakeClient.new(bad)
    proposal = draft(twice)
    assert_equal 2, twice.calls.size
    assert_equal ["fallback", nil, PlanDrafter::FALLBACK_INTRO], [proposal.source, proposal.model, proposal.payload["intro"]]
    # Small trims: trim the 2 largest non-essential categories that have a trim (dining 290, clothing 100); groceries is essential.
    assert_equal({ "groceries" => ["keep", "410.00"], "dining-out" => ["trim", "260.00"], "entertainment" => ["keep", "20.00"],
                   "clothing" => ["trim", "90.00"] }, picks(proposal))
    assert_equal PlanDrafter::FALLBACK_REASONS, proposal.payload["categories"].select { |c| c["option"] == "trim" }.map { |c| c["reason"] }
    assert_equal 2, draft(FakeClient.new(AnthropicClient::BadOutput.new("cut off"), answer(GOOD))).payload["categories"].count { |c| c["option"] == "trim" },
                 "a garbled answer gets the retry too"
  end

  test "\"Push me a bit\" falls back like small trims: the 2 largest non-essentials trimmed, never a stretch (owner, 2026-11-28)" do
    answers("change_appetite" => "push")
    proposal = draft(FakeClient.new(AiBudget::Exceeded.new("cap")))
    assert_equal "fallback", proposal.source
    # Push offers stretch for dining (230), entertainment (15) and clothing (80), but the fallback only trims:
    # dining 290 → 260 and clothing 100 → 90; groceries (essential) and entertainment (no trim) keep.
    assert_equal({ "groceries" => ["keep", "410.00"], "dining-out" => ["trim", "260.00"], "entertainment" => ["keep", "20.00"],
                   "clothing" => ["trim", "90.00"] }, picks(proposal))
    assert_not(proposal.payload["categories"].any? { |c| c["option"] == "stretch" })
  end

  test "a refusal, an outage or the AI cap → the fallback at once (no retry); keep everything never trims" do
    [AnthropicClient::Refused.new("no"), AnthropicClient::Unavailable.new("down"), AiBudget::Exceeded.new("cap")].each do |error|
      answers("change_appetite" => "trim")
      client = FakeClient.new(error)
      assert_equal "fallback", draft(client).source, error.class.name
      assert_equal 1, client.calls.size
    end
    answers("change_appetite" => "keep")
    proposal = draft(FakeClient.new(answer([], intro: "Your usual spending, as it is.")))
    assert_equal ["model", "Your usual spending, as it is."], [proposal.source, proposal.payload["intro"]]
    assert(picks(proposal).values.all? { |option, _| option == "keep" }, "keep things as they are: all keep, whatever the model says")
    assert(picks(draft(FakeClient.new(AiBudget::Exceeded.new("cap")))).values.all? { |o, _| o == "keep" })
  end

  test "goal order (D-032): the user's order wins; the model's only when they didn't answer; a bad order is dropped" do
    goals = [{ "kind" => "purchase", "name" => "Bike", "amount" => "400.00" }, { "kind" => "emergency_fund", "amount" => "2000.00" }]
    answers("change_appetite" => "keep", "goals" => goals)
    assert_equal %w[goal_1 goal_0], draft(FakeClient.new(answer([], goal_order: %w[goal_1 goal_0]))).payload["goal_order"]
    assert_equal %w[goal_0 goal_1], draft(FakeClient.new(answer([], goal_order: %w[goal_1]))).payload["goal_order"]
    answers("change_appetite" => "keep", "goals" => goals, "follow_ups" => { "goal_priority" => [0, 1] })
    assert_equal %w[goal_0 goal_1], draft(FakeClient.new(answer([], goal_order: %w[goal_1 goal_0]))).payload["goal_order"]
  end

  test "request capture (§9 automated 7): no merchant names, descriptions, account names, goal names, amounts or dates" do
    answers("change_appetite" => "push", "pay" => { "frequency" => "biweekly", "next_pay_on" => "2026-11-27", "typical_amount" => "2315.22" },
            "bills" => [{ "name" => "VERIZON WIRELESS", "amount" => "65.00", "day" => 12, "category" => "utilities" }],
            "goals" => [{ "kind" => "purchase", "name" => "Trip to Lisbon", "amount" => "3000.00" }],
            "follow_ups" => { "irregular_income_floor" => "1800.00", "biggest_trim_ok" => "a_little" })
    client = FakeClient.new(answer(GOOD))
    draft(client)
    sent = client.calls.first.values_at(:system, :user).join("\n")
    ["HARBOR BEAN", "GREENLEAF", "CINEMA", "THREADS", "ACME", "OAK PROPERTY", "VERIZON", accounts(:one_checking).name, "Lisbon",
     "2315", "4630", "3000", "1800", "410", "290", "260", "2026-"].each do |secret|
      assert_not_includes sent, secret
    end
    assert_includes sent, "Dining Out", "category names are allowed (category level)"
    assert_includes sent, "a_little", "follow-up choices are allowed"
    assert_not_includes sent, "irregular_income_floor", "the floor is an amount, so it isn't sent"
  end
end
