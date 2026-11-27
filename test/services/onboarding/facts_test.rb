require "test_helper"

# ON1: SPEC_ONBOARDING_PLAN §9 automated 1. "Today" is Thu 2026-11-26 (UTC).
class Onboarding::FactsTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 26, 12)

  setup do
    @user = users(:one)
    cat = ->(name, slug, kind, fv, pos) { Category.create!(name:, slug:, kind:, fixed_variable: fv, active: true, position: pos) }
    @income = cat.("Income", "income", "income", nil, 20)
    @rent = cat.("Rent", "rent", "spending", "fixed", 10)
    @utilities = cat.("Utilities", "utilities", "spending", "fixed", 11)
    @groceries = cat.("Groceries", "groceries", "spending", "variable", 1)
    @transfers = cat.("Transfers", "transfers", "transfer", nil, 21)
    @checking = accounts(:one_checking)
    @n = 0
  end

  def row(on, amount, category, account: @checking, description: nil)
    @n += 1
    account.transactions.create!(posted_on: Date.parse(on), amount:, description: description || "ROW #{@n}", category:,
                                 categorization_source: category ? "rule" : "none")
  end

  def facts = Onboarding::Facts.call(@user, now: NOW)
  def pay = facts[:pay_pattern]
  def d(s) = Date.parse(s)

  test "every 2 weeks: all gaps 14; next payday after today" do
    %w[2026-09-04 2026-09-18 2026-10-02 2026-10-16 2026-10-30 2026-11-13].each { |day| row(day, "2300", @income) }
    assert_equal ["biweekly", d("2026-11-13"), BigDecimal("2300"), d("2026-11-27")], pay.values_at(:frequency, :last_pay_on, :typical_amount, :next_pay_on)
  end

  test "weekly" do
    %w[2026-10-30 2026-11-06 2026-11-13 2026-11-20].each { |day| row(day, "700", @income) }
    assert_equal ["weekly", d("2026-11-27")], pay.values_at(:frequency, :next_pay_on)
  end

  test "twice a month: the 1st and the 15th (gaps 14–17), next is Dec 1" do
    %w[2026-09-01 2026-09-15 2026-10-01 2026-10-15 2026-11-02 2026-11-16].each { |day| row(day, "1500", @income) }
    assert_equal ["semimonthly", d("2026-12-01")], pay.values_at(:frequency, :next_pay_on), "early days 1, 1, 2 → median 1"
  end

  test "about half a month apart but drifting days isn't twice a month" do
    # gaps 12, 18, 17, 14, 16; late days 15, 19, 20 spread 5 (> 3)
    %w[2026-09-03 2026-09-15 2026-10-03 2026-10-20 2026-11-03 2026-11-19].each { |day| row(day, "1500", @income) }
    assert_equal "irregular", pay[:frequency]
  end

  test "monthly; median of amounts" do
    row("2026-09-28", "4100", @income)
    row("2026-10-28", "4000", @income)
    row("2026-11-27", "9999", @income) # after today: not counted
    row("2026-11-25", "4200", @income) # gap 28
    assert_equal ["monthly", BigDecimal("4100"), d("2026-12-25")], pay.values_at(:frequency, :typical_amount, :next_pay_on)
  end

  test "irregular: odd gaps, one deposit, or none; small deposits and other accounts don't count" do
    %w[2026-09-03 2026-09-25 2026-10-04 2026-11-10].each { |day| row(day, "900", @income) }
    assert_equal "irregular", pay[:frequency]
    Transaction.where(account: @checking).where.not(category_id: nil).delete_all
    row("2026-11-10", "900", @income)
    row("2026-11-17", "150", @income) # under $200
    savings = @user.accounts.create!(name: "Savings", kind: "savings", purpose: "savings")
    row("2026-11-17", "900", @income, account: savings) # not a spending/bills account
    assert_equal ["irregular", d("2026-11-10"), nil], pay.values_at(:frequency, :last_pay_on, :next_pay_on)
  end

  test "side income: monthly median over the last 3 full months, transfers left out, only from $50" do
    venmo = @user.accounts.create!(name: "Venmo", kind: "p2p", purpose: "side_income")
    row("2026-08-10", "100", nil, account: venmo)        # Aug 100 (the 3 full months are Aug, Sep, Oct)
    row("2026-09-10", "300", nil, account: venmo)        # Sep 300
    row("2026-10-05", "200", nil, account: venmo)        # Oct 200 + 210 = 410
    row("2026-10-20", "210", @income, account: venmo)
    row("2026-10-21", "-50", nil, account: venmo)        # money out: ignored
    row("2026-09-20", "500", @transfers, account: venmo) # a transfer: left out of September
    row("2026-11-06", "999", nil, account: venmo)        # this month isn't full yet: not counted
    assert_equal({ monthly: BigDecimal("300"), account_name: "Venmo" }, facts[:side_income], "Aug 100, Sep 300, Oct 410 → median 300")
    Transaction.where(account: venmo).delete_all
    row("2026-10-05", "40", nil, account: venmo)
    assert_nil facts[:side_income], "below $50"
  end

  test "likely bills: same merchant in 2 of the last 3 full months, ±10% and ±3 days" do
    row("2026-08-01", "-1850", @rent, description: "OAK PROPERTY RENT")
    row("2026-09-01", "-1850", @rent, description: "OAK PROPERTY RENT")
    row("2026-10-02", "-1850", @rent, description: "OAK PROPERTY RENT")
    row("2026-09-12", "-65", @utilities, description: "VERIZON WIRELESS")
    row("2026-10-14", "-70", @utilities, description: "VERIZON WIRELESS") # median 67.50: 65 and 70 within 10%
    row("2026-09-09", "-60", @utilities, description: "PG&E WEB ONLINE")
    row("2026-10-09", "-140", @utilities, description: "PG&E WEB ONLINE") # amounts too far apart
    row("2026-09-03", "-80", @utilities, description: "WATER CO")
    row("2026-10-20", "-80", @utilities, description: "WATER CO")         # days too far apart
    row("2026-10-04", "-15", @utilities, description: "ONE-OFF FEE")      # one month only
    row("2026-09-15", "-50", @groceries, description: "GROCER")
    row("2026-10-15", "-50", @groceries, description: "GROCER")           # flexible: not a bill
    bills = facts[:likely_bills]
    assert_equal [["OAK PROPERTY RENT", BigDecimal("1850"), 1, "rent"], ["VERIZON WIRELESS", BigDecimal("67.5"), 13, "utilities"]],
                 bills.map { |b| b.values_at(:name, :amount, :day, :category) }, "rent: Sep and Oct only (August is 4 months back)"
  end

  test "another user's rows never count" do
    %w[2026-10-16 2026-10-30 2026-11-13].each { |day| row(day, "2300", @income, account: accounts(:two_checking)) }
    assert_equal ["irregular", nil], pay.values_at(:frequency, :last_pay_on)
  end
end
