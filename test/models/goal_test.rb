require "test_helper"

# G1 (goals): per-type rules, computed progress, database constraints.
class GoalTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  def saving(**attrs) = @user.goals.new({ goal_type: "upcoming_payment", name: "Car insurance", target_amount: "600", target_date: Date.new(2027, 3, 1) }.merge(attrs))
  def debt(**attrs) = @user.goals.new({ goal_type: "debt_payoff", name: "Card", starting_balance: "5000", apr: "22.9", monthly_payment: "200" }.merge(attrs))

  test "each type needs its own fields and refuses the others" do
    assert saving.valid?
    assert saving(goal_type: "purchase", target_date: nil).valid?, "a purchase may be undated (emergency fund)"
    assert saving(target_date: nil).invalid?, "an upcoming payment needs a date"
    assert saving(target_amount: "0").invalid?
    assert saving(apr: "5").invalid?
    assert saving(starting_balance: "-1").invalid?
    assert debt.valid?
    assert debt(starting_balance: "0").invalid?
    assert debt(apr: nil).invalid?
    assert debt(apr: "101").invalid?
    assert debt(apr: "0").valid?, "0% APR is a real case"
    assert debt(monthly_payment: "0").invalid?
    assert debt(target_amount: "100").invalid?
    assert debt(target_date: Date.new(2027, 1, 1)).invalid?
    assert saving(goal_type: "savings").invalid?
    assert saving(status: "paused").invalid?
    assert saving(name: " ").invalid?
  end

  test "saved = starting amount + set-asides; remaining never below 0" do
    g = saving(starting_balance: "100").tap(&:save!)
    travel_to Time.utc(2026, 11, 26, 12) do
      g.contributions.create!(kind: "set_aside", amount: "62.50", contributed_on: Date.new(2026, 11, 20))
      g.contributions.create!(kind: "set_aside", amount: "37.50", contributed_on: Date.new(2026, 11, 26))
    end
    g.reload
    assert_equal [BigDecimal("200"), BigDecimal("400")], [g.saved, g.remaining]
    assert_nil g.balance
    travel_to(Time.utc(2026, 11, 26, 12)) { g.contributions.create!(kind: "set_aside", amount: "500", contributed_on: Date.new(2026, 11, 26)) }
    assert_equal 0, g.reload.remaining
  end

  test "debt balance = latest update by date, else the starting balance; undo by delete" do
    g = debt.tap(&:save!)
    assert_equal BigDecimal("5000"), g.balance
    travel_to Time.utc(2026, 11, 26, 12) do
      g.contributions.create!(kind: "balance_update", balance_after: "4700", contributed_on: Date.new(2026, 11, 20))
      @late = g.contributions.create!(kind: "balance_update", balance_after: "4800", contributed_on: Date.new(2026, 10, 20)) # entered later, older date
    end
    assert_equal BigDecimal("4700"), g.reload.balance, "by date, not entry order"
    last = g.contributions.order(:contributed_on).last
    last.destroy!
    assert_equal BigDecimal("4800"), g.reload.balance
    assert_equal BigDecimal("4800"), g.remaining
    assert_nil g.saved
  end

  test "contributions: right kind for the goal, positive, never in the future (user's zone)" do
    s = saving.tap(&:save!)
    d = debt.tap(&:save!)
    FinancialProfile.find_or_create_by!(user: @user).update!(time_zone: "Pacific/Auckland")
    travel_to Time.utc(2026, 11, 26, 12) do # already Nov 27 in Auckland
      assert s.contributions.new(kind: "set_aside", amount: "10", contributed_on: Date.new(2026, 11, 27)).valid?
      assert s.contributions.new(kind: "set_aside", amount: "10", contributed_on: Date.new(2026, 11, 28)).invalid?
      assert s.contributions.new(kind: "balance_update", balance_after: "10", contributed_on: Date.new(2026, 11, 26)).invalid?
      assert d.contributions.new(kind: "set_aside", amount: "10", contributed_on: Date.new(2026, 11, 26)).invalid?
      assert s.contributions.new(kind: "set_aside", amount: "0", contributed_on: Date.new(2026, 11, 26)).invalid?
      assert s.contributions.new(kind: "set_aside", amount: "10", balance_after: "1", contributed_on: Date.new(2026, 11, 26)).invalid?
      assert d.contributions.new(kind: "balance_update", balance_after: "0", contributed_on: Date.new(2026, 11, 26)).valid?, "paid off"
      assert d.contributions.new(kind: "balance_update", balance_after: "-1", contributed_on: Date.new(2026, 11, 26)).invalid?
      assert s.contributions.new(kind: "set_aside", amount: "10", contributed_on: Date.new(2026, 11, 26), note: "x" * 201).invalid?
      assert s.contributions.new(kind: "linked_transfer", amount: "10", contributed_on: Date.new(2026, 11, 26)).invalid?, "linking isn't built"
    end
  end

  test "the database refuses what validation would" do
    s = saving.tap(&:save!)
    d = debt.tap(&:save!)
    [[s, { target_amount: nil }], [s, { target_date: nil }], [s, { apr: 5 }], [s, { goal_type: "x" }], [s, { status: "x" }],
     [s, { source: "x" }], [d, { apr: 101 }], [d, { monthly_payment: nil }], [d, { starting_balance: 0 }], [d, { target_amount: 1 }]].each do |goal, attrs|
      assert_raises(ActiveRecord::StatementInvalid, attrs.inspect) { Goal.transaction(requires_new: true) { goal.update_columns(attrs) } }
    end
    s.reload # update_columns changed the in-memory copy before the database refused
    c = travel_to(Time.utc(2026, 11, 26, 12)) { s.contributions.create!(kind: "set_aside", amount: "10", contributed_on: Date.new(2026, 11, 26)) }
    [{ amount: 0 }, { amount: nil }, { balance_after: 5 }, { kind: "balance_update" }, { note: "x" * 201 }].each do |attrs|
      assert_raises(ActiveRecord::StatementInvalid, attrs.inspect) { GoalContribution.transaction(requires_new: true) { c.update_columns(attrs) } }
    end
    assert_raises(ActiveRecord::InvalidForeignKey) { Goal.transaction(requires_new: true) { Goal.where(id: s.id).delete_all } }
  end
end
