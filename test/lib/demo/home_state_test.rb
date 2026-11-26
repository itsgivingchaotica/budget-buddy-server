require "test_helper"

# demo:home_state: the guards, and that each state gives Home what it promises.
class Demo::HomeStateTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 26, 12) # Thursday; the week is Mon 11-23 … Sun 11-29

  setup do
    @user = users(:one)
    { "groceries" => 1, "dining-out" => 2, "transportation" => 3, "entertainment" => 4, "clothing" => 5 }.each do |slug, pos|
      Category.create!(name: slug.titleize, slug:, kind: "spending", fixed_variable: "variable", active: true, position: pos)
    end
    { "rent" => 10, "utilities" => 11, "subscriptions" => 12 }.each do |slug, pos|
      Category.create!(name: slug.titleize, slug:, kind: "spending", fixed_variable: "fixed", active: true, position: pos)
    end
    Category.create!(name: "Income", slug: "income", kind: "income", active: true, position: 20)
    travel_to NOW
  end

  teardown { travel_back }

  def run_state(state) = Demo::HomeState.call(state:, email: @user.email, env: "development", now: NOW)

  test "refused outside development, for an unknown state, or an unknown email" do
    assert_raises(Demo::HomeState::Refused) { Demo::HomeState.call(state: "normal", email: @user.email, env: "test") }
    assert_raises(Demo::HomeState::Refused) { Demo::HomeState.call(state: "normal", email: @user.email, env: "production") }
    assert_raises(Demo::HomeState::Refused) { Demo::HomeState.call(state: "party", email: @user.email, env: "development") }
    assert_raises(Demo::HomeState::Refused) { Demo::HomeState.call(state: "normal", email: "nobody@example.invalid", env: "development") }
  end

  test "normal, over and no_plan give the promised Home, and each run replaces the last" do
    run_state("normal")
    o = WeeklyOutlook.call(@user, now: NOW)
    assert_equal ["ok", Date.new(2026, 11, 26), BigDecimal("107.35")], [o[:state], o[:data_through], o[:left_to_spend][:spent]]
    assert_operator o[:left_to_spend][:left], :>, 100, "comfortably under: 7 × 1200/30 - 107.35 = 172.65"
    assert_equal [["Phone", true, false], ["Rent", false, false], ["Streaming", false, false]],
                 o[:bills_due][:items].map { |b| b.values_at(:name, :paid, :overdue) }
    assert_equal ["Car insurance"], o[:goal_contributions].map { |g| g[:name] }

    run_state("over")
    o = WeeklyOutlook.call(@user, now: NOW)
    assert_in_delta(-20, o[:left_to_spend][:left].to_f, 1, "about $20 over")
    assert_equal 1, @user.goals.count, "replaced, not added"
    assert_equal 3, @user.obligations.count
    assert_equal 1, Import.where(filename: Demo::HomeState::FILENAME).count, "the earlier run's week rows are gone"

    run_state("no_plan")
    o = WeeklyOutlook.call(@user, now: NOW)
    assert_equal "no_plan", o[:state]
    assert_equal [0, 0, 0], [@user.category_budgets.count, @user.obligations.count, @user.goals.count]
    assert transactions(:one_coffee).reload, "imported history stays"
  end

  test "plan: an over row, No budget yet, uncategorized, a paid bill, three goals incl. a debt" do
    run_state("plan")
    r = SpendingAnalytics.budget_vs_actual(@user, month: Date.new(2026, 11, 1))
    dining = r[:categories].find { |c| c[:category] == "dining-out" }
    # this week 6.40 + 14.75, plus 40.00 on the 1st = 61.15; budget = 61.15 - 6, down = 55
    assert_equal [BigDecimal("61.15"), BigDecimal("55"), "over"], dining.values_at(:spent, :budget, :status)
    assert(r[:categories].reject { |c| c[:category] == "dining-out" }.all? { |c| c[:status] == "under" }, "only Dining Out is over")
    assert_equal [["clothing", BigDecimal("63.5")]], r[:unbudgeted].map { |u| u.values_at(:category, :spent) }
    assert_equal BigDecimal("25"), r[:uncategorized], "the transfer to a person went to review"
    assert_equal ["Car fund", "Car insurance", "Pay off the card"], @user.goals.pluck(:name).sort
    card = @user.goals.find_by!(name: "Pay off the card")
    assert_equal [BigDecimal("1840"), 28], [card.balance, GoalCalculator.for(card, now: NOW).call[:percent_paid]]
    electric = @user.obligations.find_by!(name: "Electric")
    assert_equal "paid", Bills.current(electric, today: Date.new(2026, 11, 26))[:status]
    run_state("plan")
    assert_equal 3, @user.goals.count, "running it again replaces, not adds"
  end
end
