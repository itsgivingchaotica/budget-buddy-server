require "test_helper"

# W1: SPEC_LEFT_TO_SPEND.md §10 worked examples 1–11, with the spec's own
# figures, plus the states, bills and goals around them. Weeks start on
# Monday (the default); time zone UTC.
class WeeklyOutlookTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    cat = ->(name, slug, kind, fv, pos) { Category.create!(name:, slug:, kind:, fixed_variable: fv, active: true, position: pos) }
    @groceries = cat.("Groceries", "groceries", "spending", "variable", 1)
    @dining = cat.("Dining Out", "dining-out", "spending", "variable", 2)
    @entertainment = cat.("Entertainment", "entertainment", "spending", "variable", 3)
    @clothing = cat.("Clothing", "clothing", "spending", "variable", 4)
    @rent = cat.("Rent", "rent", "spending", "fixed", 10)
    @utilities = cat.("Utilities", "utilities", "spending", "fixed", 11)
    @income = cat.("Income", "income", "income", nil, 20)
    @transfers = cat.("Transfers", "transfers", "transfer", nil, 21)
    @checking = accounts(:one_checking)
    @n = 0
  end

  def d(s) = Date.parse(s)
  def b(s) = BigDecimal(s)
  def at(day) = Time.utc(*day.split("-").map(&:to_i), 12)

  def row(on, amount, category = nil, account: @checking)
    @n += 1
    account.transactions.create!(posted_on: d(on), amount:, description: "ROW #{@n}", category:,
                                 categorization_source: category ? "rule" : "none")
  end

  def budgets(month, amounts)
    amounts.each { |c, a| @user.category_budgets.create!(category: c, amount: a, effective_from: d(month)) }
  end

  def november = budgets("2026-11-01", @groceries => "400", @dining => "150", @entertainment => "90") # total 640

  def outlook(day) = WeeklyOutlook.call(@user, now: at(day))
  def lts(day) = outlook(day)[:left_to_spend]

  test "example 1: normal week — 7 × 640 / 30 = 149.33; spent 85.60; left 63.73" do
    november
    row("2026-11-17", "-62.10", @groceries)
    row("2026-11-22", "-23.50", @dining)
    o = outlook("2026-11-22")
    assert_equal ["ok", d("2026-11-22"), { start: d("2026-11-16"), end: d("2026-11-22") }], o.values_at(:state, :data_through, :week)
    l = o[:left_to_spend]
    assert_equal [b("149.33"), b("85.60"), b("63.73")], l.values_at(:allowance, :spent, :left).map { |v| v.round(2) }
    assert_equal [["groceries", b("93.33"), b("62.10"), b("31.23")], ["dining-out", b("35.00"), b("23.50"), b("11.50")],
                  ["entertainment", b("21.00"), b("0"), b("21.00")]],
                 l[:by_category].map { |c| [c[:category], *c.values_at(:allowance, :spent, :left).map { |v| v.round(2) }] }
  end

  test "example 2: a week across a month with a budget change — 1 × 640/30 + 6 × 700/31 = 156.82" do
    november
    budgets("2026-12-01", @groceries => "450", @dining => "160", @entertainment => "90") # total 700
    row("2026-12-02", "-1.00", @groceries)
    o = outlook("2026-12-02")
    assert_equal({ start: d("2026-11-30"), end: d("2026-12-06") }, o[:week])
    assert_equal b("156.82"), o[:left_to_spend][:allowance].round(2)
  end

  test "example 3: overspent — left −21.67" do
    november
    row("2026-11-18", "-171.00", @groceries)
    l = lts("2026-11-22")
    assert_equal [b("171"), b("-21.67")], [l[:spent], l[:left].round(2)]
  end

  test "example 4: a refund in the same category the same week — spent 25.00" do
    november
    row("2026-11-17", "-40.00", @groceries)
    row("2026-11-19", "15.00", @groceries)
    assert_equal b("25"), lts("2026-11-22")[:spent]
  end

  test "example 5: a confirmed transfer contributes 0" do
    november
    savings = @user.accounts.create!(name: "Savings", kind: "savings", purpose: "savings")
    row("2026-11-18", "-200.00", @transfers)
    row("2026-11-18", "200.00", @transfers, account: savings)
    row("2026-11-22", "-1.00", @groceries, account: savings)
    row("2026-11-22", "-1.00", @groceries)
    assert_equal b("2"), lts("2026-11-22")[:spent]
  end

  test "example 6: stale data wins over no data this week — allowance shown, spent 0" do
    november
    row("2026-11-10", "-30.00", @groceries)
    o = outlook("2026-11-22")
    assert_equal ["stale", d("2026-11-10")], o.values_at(:state, :data_through)
    assert_equal [b("149.33"), b("0")], [o[:left_to_spend][:allowance].round(2), o[:left_to_spend][:spent]]
  end

  test "no data this week (but not stale): full allowance" do
    november
    row("2026-11-15", "-30.00", @groceries) # a Sunday, before the week
    o = outlook("2026-11-18")
    assert_equal ["no_data_this_week", b("0")], [o[:state], o[:left_to_spend][:spent]]
  end

  test "example 7: one uncategorized −18.00 counts, uncategorized_count 1" do
    november
    row("2026-11-20", "-18.00")
    row("2026-11-22", "-1.00", @dining)
    l = lts("2026-11-22")
    assert_equal [b("19"), b("18"), 1], l.values_at(:spent, :uncategorized_spent, :uncategorized_count)
  end

  test "example 8: no flexible budgets — no_plan, even with spending" do
    @user.category_budgets.create!(category: @groceries, amount: "400", effective_from: d("2026-12-01")) # next month only
    row("2026-11-20", "-18.00", @groceries)
    assert_equal "no_plan", outlook("2026-11-22")[:state]
  end

  test "example 9: bills — the next 7 days, plus earlier this week (unpaid: overdue; paid: listed as paid)" do
    november
    row("2026-11-21", "-1.00", @groceries)
    ob = ->(name, first, category = @rent) { @user.obligations.create!(name:, amount: "1200", category:, first_due_on: d(first), recurrence: "monthly") }
    rent = ob.("Rent", "2026-01-23")
    phone = ob.("Phone", "2026-01-17", @utilities)
    paid = ob.("Internet", "2026-01-18", @utilities)
    paid.payments.create!(due_on: d("2026-11-18"), paid_on: d("2026-11-18"))
    ob.("Water", "2026-01-28", @utilities) # today + 7: outside
    ob.("Old", "2026-01-12", @utilities)   # before this week: not listed
    bills = travel_to(at("2026-11-21")) { outlook("2026-11-21")[:bills_due] }
    assert_equal({ start: d("2026-11-21"), end: d("2026-11-27") }, bills[:window])
    assert_equal [[phone.id, d("2026-11-17"), false, true], [paid.id, d("2026-11-18"), true, false], [rent.id, d("2026-11-23"), false, false]],
                 bills[:items].map { |i| i.values_at(:obligation_id, :due_on, :paid, :overdue) },
                 "a bill paid earlier this week stays listed so Mark paid can be undone"
  end

  test "example 10: uncategorized money in is ignored — spent 58.00, uncategorized_count 2" do
    november
    row("2026-11-17", "-40.00", @groceries)
    row("2026-11-18", "-18.00")
    row("2026-11-20", "500.00")
    row("2026-11-22", "-0.01", @rent) # fixed: excluded, only sets data_through
    l = lts("2026-11-22")
    assert_equal [b("58"), 2], l.values_at(:spent, :uncategorized_count)
    assert_includes outlook("2026-11-22")[:assumptions].last, "Includes 2 uncategorized transactions"
  end

  test "example 11: a refund in another category doesn't offset — spent 40.00" do
    november
    row("2026-11-17", "-40.00", @groceries)
    row("2026-11-22", "60.00", @clothing)
    l = lts("2026-11-22")
    assert_equal b("40"), l[:spent]
    assert_equal [b("0"), b("0")], l[:by_category].find { |c| c[:category] == "clothing" }.values_at(:allowance, :spent)
  end

  test "excluded: fixed categories, income, archived accounts, rows after today; a $0 budget adds nothing" do
    budgets("2026-11-01", @groceries => "300", @dining => "0")
    row("2026-11-17", "-1200.00", @rent)
    row("2026-11-17", "3000.00", @income)
    row("2026-11-18", "-12.00", @dining)
    old = @user.accounts.create!(name: "Old", kind: "checking", purpose: "spending")
    row("2026-11-18", "-500.00", @groceries, account: old)
    old.archive!
    row("2026-11-20", "-1.00", @groceries)
    row("2026-11-21", "-77.00", @groceries) # tomorrow
    l = lts("2026-11-20")
    assert_equal [b("70"), b("13")], [l[:allowance], l[:spent]], "7 × 300/30; dining's 12 counts with a $0 budget"
  end

  test "spending counts only through data_through, the earliest account's latest row" do
    november
    savings = @user.accounts.create!(name: "Savings", kind: "savings", purpose: "savings")
    row("2026-11-17", "-10.00", @groceries, account: savings)
    row("2026-11-17", "-5.00", @groceries)
    row("2026-11-21", "-50.00", @groceries)
    o = outlook("2026-11-22")
    assert_equal [d("2026-11-17"), b("15")], [o[:data_through], o[:left_to_spend][:spent]]
  end

  test "goal contributions this week: dated saving goals still short; never subtracted" do
    november
    row("2026-11-22", "-1.00", @groceries)
    travel_to(at("2026-11-16")) do
      @user.goals.create!(goal_type: "upcoming_payment", name: "Car insurance", target_amount: "175", target_date: d("2026-12-13"))
      @user.goals.create!(goal_type: "purchase", name: "Fund", target_amount: "999") # undated: not listed
      @user.goals.create!(goal_type: "purchase", name: "Bike", target_amount: "100", target_date: d("2026-12-20"),
                          starting_balance: "100") # reached: not listed
      @user.goals.create!(goal_type: "debt_payoff", name: "Card", starting_balance: "900", apr: "20", monthly_payment: "50")
    end
    car = @user.goals.find_by!(name: "Car insurance")
    travel_to(at("2026-11-18")) { car.contributions.create!(kind: "set_aside", amount: "10", contributed_on: d("2026-11-18")) }
    o = outlook("2026-11-22")
    # weeks Nov 16 … the week of Dec 13 (Dec 7): 4 weeks; 175 / 4 = 43.75
    assert_equal [{ goal_id: car.id, name: "Car insurance", needed_this_week: b("43.75"), set_aside_this_week: b("10"),
                    still_needed_this_week: b("33.75"), target_date: d("2026-12-13") }], o[:goal_contributions]
    assert_equal b("149.33") - b("1"), o[:left_to_spend][:left].round(2), "bills and goals don't change left"
  end

  test "another user's budgets, transactions, bills and goals never affect the result" do
    november
    row("2026-11-22", "-1.00", @groceries)
    two = users(:two)
    two.category_budgets.create!(category: @clothing, amount: "3000", effective_from: d("2026-11-01"))
    accounts(:two_checking).transactions.create!(posted_on: d("2026-11-20"), amount: "-999", description: "THEIRS", category: @groceries, categorization_source: "rule")
    two.obligations.create!(name: "Their rent", amount: "1", category: @rent, first_due_on: d("2026-11-23"), recurrence: "monthly")
    two.goals.create!(goal_type: "upcoming_payment", name: "Theirs", target_amount: "50", target_date: d("2026-12-01"))
    o = outlook("2026-11-22")
    assert_equal [b("149.33"), b("1")], [o[:left_to_spend][:allowance].round(2), o[:left_to_spend][:spent]]
    assert_empty o[:bills_due][:items]
    assert_empty o[:goal_contributions]
  end

  test "the user's own week start and time zone" do
    FinancialProfile.find_or_create_by!(user: @user).update!(week_starts_on: FinancialProfile::SUNDAY, time_zone: "Pacific/Auckland")
    november
    row("2026-11-22", "-5.00", @groceries)
    o = WeeklyOutlook.call(@user, now: Time.utc(2026, 11, 21, 12)) # already Sun Nov 22 in Auckland
    assert_equal [d("2026-11-22"), { start: d("2026-11-22"), end: d("2026-11-28") }], o.values_at(:today, :week)
    assert_equal b("5"), o[:left_to_spend][:spent]
  end
end
