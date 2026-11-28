require "test_helper"

# PL1 (plan drafting): SPEC_ONBOARDING_PLAN §6.1–6.2 as amended by D-032,
# §9 automated 2 and 3. Hand-calculated examples. "Today" is Thu 2026-11-26
# (UTC, weeks start Monday). Rows on Jul 1 and Nov 20 make Jul–Oct full
# months the data covers (4 months).
class PlanFiguresTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 26, 12)

  setup do
    @user = users(:one)
    cat = ->(name, slug, kind, fv, pos) { Category.create!(name:, slug:, kind:, fixed_variable: fv, active: true, position: pos) }
    @groceries = cat.("Groceries", "groceries", "spending", "variable", 1)
    @dining = cat.("Dining Out", "dining-out", "spending", "variable", 2)
    @fun = cat.("Entertainment", "entertainment", "spending", "variable", 3)
    @rent = cat.("Rent", "rent", "spending", "fixed", 10)
    @debt = cat.("Debt Payments", "debt-payments", "spending", "fixed", 11)
    @income = cat.("Income", "income", "income", nil, 20)
    @checking = accounts(:one_checking)
    @n = 0
    travel_to NOW
  end

  teardown { travel_back }

  def row(on, amount, category, account: @checking)
    @n += 1
    account.transactions.create!(posted_on: Date.parse(on), amount:, description: "ROW #{@n}", category:, categorization_source: category ? "rule" : "none")
  end

  def answers(hash)
    FinancialProfile.find_or_create_by!(user: @user).update!(answers: hash)
    @user.reload
  end

  # Jul 260 · Aug 300 · Sep 310 · Oct 280 dining; Jul 400 · Aug 412 · Sep 388 · Oct 420 groceries; 20 a month on fun.
  def spending
    { "07" => [260, 400], "08" => [300, 412], "09" => [310, 388], "10" => [280, 420] }.each do |m, (d, g)|
      row("2026-#{m}-10", -d, @dining)
      row("2026-#{m}-12", -g, @groceries)
      row("2026-#{m}-14", -20, @fun)
    end
    row("2026-07-01", -1, @rent)
    row("2026-11-20", -1, @rent)
  end

  def candidates(hash = {}) = (answers(hash) && PlanCandidates.call(@user, hash))
  def options(list, slug) = list[:categories].find { |c| c[:category] == slug }[:options]

  test "candidates: usual = median of the full months; keep up to $5, trim and stretch to the nearest $5 (§6.1)" do
    spending
    list = candidates("change_appetite" => "push")
    assert_equal 4, list[:months]
    # Dining: 260, 280, 300, 310 → median (280 + 300) / 2 = 290. keep 290 (already a multiple of 5);
    # trim 290 × 0.9 = 261 → 260; stretch 290 × 0.8 = 232 → 230.
    dining = list[:categories].find { |c| c[:category] == "dining-out" }
    assert_equal BigDecimal("290"), dining[:usual]
    assert_equal({ "keep" => 290, "trim" => 260, "stretch" => 230 }, dining[:options])
    # Groceries (essential): 388, 400, 412, 420 → median 406. keep 410; trim 365.4 → 365; never stretch.
    assert_equal({ "keep" => 410, "trim" => 365 }, options(list, "groceries"))
    # Entertainment: usual 20 → keep 20; trim 18 → 20 isn't $5 below keep → no trim;
    # stretch 16 → 15 is $5 below keep → offered for "push".
    assert_equal({ "keep" => 20, "stretch" => 15 }, options(list, "entertainment"))
    assert_equal({ "keep" => 290, "trim" => 260 }, options(candidates("change_appetite" => "trim"), "dining-out"), "no stretch unless push")
    assert_equal({ "keep" => 20 }, options(candidates("change_appetite" => "trim"), "entertainment"))
  end

  test "candidates: fewer than 2 full months → keep only, marked new; the trim follow-up narrows the top category" do
    row("2026-10-01", -1, @rent)
    row("2026-10-12", -406, @groceries)
    row("2026-11-20", -1, @rent)
    list = candidates("change_appetite" => "push")
    assert_equal 1, list[:months]
    assert_equal [{ "keep" => 410 }, true], list[:categories].map { |c| [c[:options], c[:new]] }.first

    spending
    # Groceries (406) is the top category: "Leave it alone" → keep only; dining unaffected.
    list = candidates("change_appetite" => "push", "follow_ups" => { "biggest_trim_ok" => "leave_it" })
    assert_equal({ "keep" => 410 }, options(list, "groceries"))
    assert_equal({ "keep" => 290, "trim" => 260, "stretch" => 230 }, options(list, "dining-out"))
  end

  # Income on checking: Aug 4600 · Sep 4630 · Oct 4700 (the last 3 full months) → median 4630, lowest 4600.
  def income_rows
    row("2026-07-01", -1, @rent)
    row("2026-11-20", -1, @rent)
    { "08-15" => 4600, "09-15" => 4630, "10-15" => 4700 }.each { |d, a| row("2026-#{d}", a, @income) }
  end

  def income(hash) = PlanFigures.income(answers(hash), hash, today: Date.new(2026, 11, 26), now: NOW)

  test "income (§6.2, D-032): data median unless the paycheck was changed; irregular floor or lowest month; side income" do
    income_rows
    assert_equal [BigDecimal("4630"), "median"], income("pay" => { "frequency" => "monthly" }).values_at(:monthly, :basis)
    # Paychecks found in the last 90 days: Sep 4630, Oct 4700 → typical 4665. Unchanged → still the median.
    assert_equal "median", income("pay" => { "frequency" => "monthly", "typical_amount" => "4665.00" })[:basis]
    # Changed: 2315.22 every 2 weeks × 26 / 12 = 60,195.72 / 12 = 5016.31.
    assert_equal [BigDecimal("5016.31"), "your_paycheck"],
                 income("pay" => { "frequency" => "biweekly", "typical_amount" => "2315.22" }).values_at(:monthly, :basis)
    assert_equal BigDecimal("4000"), income("pay" => { "frequency" => "semimonthly", "typical_amount" => "2000.00" })[:monthly], "twice a month × 2"
    floor = income("pay" => { "frequency" => "irregular" }, "follow_ups" => { "irregular_income_floor" => "1800.00" })
    assert_equal [BigDecimal("1800"), "floor"], floor.values_at(:monthly, :basis)
    lowest = income("pay" => { "frequency" => "irregular" })
    assert_equal [BigDecimal("4600"), "lowest_month", "Based on your lowest recent month"], lowest.values_at(:monthly, :basis, :label)

    venmo = @user.accounts.create!(name: "Venmo", kind: "p2p", purpose: "side_income")
    # Aug 150 · Sep 210 · Oct 180 → median 180; small rows on Jul 1 and Nov 20 keep Aug–Oct covered for this account too.
    { "07-01" => 1, "08-20" => 150, "09-20" => 210, "10-20" => 180, "11-20" => 1 }.each { |d, a| row("2026-#{d}", a, nil, account: venmo) }
    assert_equal BigDecimal("4810"), income("pay" => { "frequency" => "monthly" }, "side_income" => "yes")[:monthly], "4630 + 180"
    assert_equal BigDecimal("4630"), income("pay" => { "frequency" => "monthly" }, "side_income" => "no")[:monthly]
  end

  def payload(income:, bills:, goals: [])
    { "income" => { "monthly" => income }, "bills" => bills, "goals" => goals,
      "categories" => [{ "category" => "dining-out", "amount" => "260.00" }, { "category" => "groceries", "amount" => "410.00" }] }
  end

  def bill(key, name, amount, category) = { "key" => key, "name" => name, "amount" => amount, "day" => 1, "category" => category, "included" => true }

  test "fit line (§6.2): committed = bills + dated goals' weekly need × 52/12 + debt payment unless a Debt Payments bill" do
    answers({})
    # Car insurance $600 due Mon 2027-01-18: weeks Nov 23 → Jan 18 = 9 → 600 / 9 = 66.67 a week (cents up)
    # → 66.67 × 52 / 12 = 288.90 a month. Emergency fund (no date): 0. Card: $120 a month.
    goals = [{ "key" => "goal_0", "kind" => "upcoming_payment", "name" => "Car insurance", "amount" => "600.00", "date" => "2027-01-18", "included" => true },
             { "key" => "goal_1", "kind" => "emergency_fund", "name" => "Emergency fund", "amount" => "2000.00", "included" => true },
             { "key" => "goal_2", "kind" => "debt_payoff", "name" => "Card", "balance" => "1200.00", "apr" => "24.99", "monthly_payment" => "120.00", "included" => true }]
    bills = [bill("bill_0", "Rent", "1500.00", "rent"), bill("bill_1", "Phone", "65.00", "utilities")]
    result = PlanFigures.compute(@user, payload(income: "3000.00", bills:, goals:), now: NOW)
    assert_equal({ "bills" => "1565.00", "goals" => "288.90", "debt" => "120.00", "total" => "1973.90" }, result["committed"])
    # Room 3000 − 1973.90 = 1026.10; everyday 260 + 410 = 670 → fits, gap 0.
    assert_equal ["1026.10", "670.00", true, "0.00"], result.values_at("room", "everyday_total", "fits", "gap")

    # A kept Debt Payments bill of 120: the card's payment isn't counted again (total unchanged).
    with_bill = PlanFigures.compute(@user, payload(income: "3000.00", bills: bills + [bill("bill_2", "Card payment", "120.00", "debt-payments")], goals:), now: NOW)
    assert_equal({ "bills" => "1685.00", "goals" => "288.90", "debt" => "0.00", "total" => "1973.90" }, with_bill["committed"])

    # Income 2000: room 26.10; 670 > 26.10 → doesn't fit by 643.90.
    tight = PlanFigures.compute(@user, payload(income: "2000.00", bills:, goals:), now: NOW)
    assert_equal ["26.10", false, "643.90"], tight.values_at("room", "fits", "gap")
    # A bill switched off isn't committed.
    off = PlanFigures.compute(@user, payload(income: "3000.00", bills: [bills[0].merge("included" => false), bills[1]], goals:), now: NOW)
    assert_equal "65.00", off["committed"]["bills"]
    # A goal switched off isn't committed either: car insurance off → goals 0, total 1565 + 120 = 1685.
    no_car = PlanFigures.compute(@user, payload(income: "3000.00", bills:, goals: [goals[0].merge("included" => false), goals[1], goals[2]]), now: NOW)
    assert_equal({ "bills" => "1565.00", "goals" => "0.00", "debt" => "120.00", "total" => "1685.00" }, no_car["committed"])
  end

  test "rent from \"Add it\" (D-032): the median Rent spending of the last 3 full months, on the usual day" do
    row("2026-07-01", -1, @groceries)
    row("2026-11-20", -1, @groceries)
    { "08-01" => 1800, "09-02" => 1850, "10-01" => 1850 }.each { |d, a| row("2026-#{d}", -a, @rent) } # median 1850, days 1, 2, 1 → 1
    bills = PlanFigures.draft_bills(@user, { "bills" => [], "follow_ups" => { "bill_missing" => "add_it" } }, today: Date.new(2026, 11, 26))
    assert_equal [{ "name" => "Rent", "amount" => "1850.00", "day" => 1, "category" => "rent", "key" => "bill_0", "included" => true, "from_spending" => true }], bills
    assert_empty PlanFigures.draft_bills(@user, { "bills" => [], "follow_ups" => { "bill_missing" => "included" } }, today: Date.new(2026, 11, 26))
  end
end
