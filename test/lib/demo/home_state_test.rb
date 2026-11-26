require "test_helper"

# demo:home_state: the guards, and that each state gives Home what it promises.
class Demo::HomeStateTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 26, 12) # Thursday; the week is Mon 11-23 … Sun 11-29

  setup do
    @user = users(:one)
    { "groceries" => 1, "dining-out" => 2, "transportation" => 3, "entertainment" => 4 }.each do |slug, pos|
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
end
