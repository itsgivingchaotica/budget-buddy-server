require "test_helper"

# G2: debt schedules. Expected values come from an independent reference
# schedule (Python Decimal, same rounding rule) and the closed-form payoff
# formula n = -ln(1 - rB/P) / ln(1 + r).
class DebtCalculatorTest < ActiveSupport::TestCase
  def calc(balance, apr, payment) = DebtCalculator.new(balance: BigDecimal(balance), apr: BigDecimal(apr), payment: BigDecimal(payment))

  test "$5,000 at 22% APR, $200 a month: 34 payments, $1,749.90 interest" do
    c = calc("5000", "22", "200")
    # closed form: r = 0.22/12, n = 33.75 → 34 payments
    s = c.schedule
    assert_equal 34, s.months
    assert_equal BigDecimal("1749.90"), s.total_interest
    assert_equal BigDecimal("91.67"), c.interest_this_month, "5000 × 0.22 / 12"
    assert_equal BigDecimal("4891.67"), s.balances.first, "5000 + 91.67 - 200"
    assert_equal BigDecimal("147.20"), s.balances[-2]
    assert_equal BigDecimal("0"), s.balances.last, "last payment 147.20 + 2.70 interest = 149.90"
    assert_not s.never_pays_off
  end

  test "+$50 a month: 26 payments, saving $464.19 and 8 months" do
    w = calc("5000", "22", "200").what_if(50)
    assert_equal [26, BigDecimal("1285.71")], [w[:schedule].months, w[:schedule].total_interest]
    assert_equal BigDecimal("464.19"), w[:interest_saved]
    assert_equal 8, w[:months_sooner]
  end

  test "the card example: $1,840 at 22.9% APR, $120 a month" do
    c = calc("1840", "22.9", "120")
    assert_equal BigDecimal("35.11"), c.interest_this_month
    assert_equal [19, BigDecimal("357.75")], [c.schedule.months, c.schedule.total_interest]
    assert_equal [BigDecimal("1755.11"), BigDecimal("1668.60"), BigDecimal("1580.44")], c.schedule.balances.first(3)
  end

  test "0% APR is plain division; 12% APR small case" do
    assert_equal [12, BigDecimal("0")], [calc("1200", "0", "100").schedule.months, calc("1200", "0", "100").schedule.total_interest]
    assert_equal [11, BigDecimal("58.98")], [calc("1000", "12", "100").schedule.months, calc("1000", "12", "100").schedule.total_interest]
  end

  test "an exact half cent of interest rounds up" do
    c = calc("1380", "22.9", "120")
    assert_equal BigDecimal("26.34"), c.interest_this_month, "1380 × 22.9 ÷ 1200 = 26.335"
    assert_equal [14, BigDecimal("192.96")], [c.schedule.months, c.schedule.total_interest]
    assert_equal BigDecimal("26.33"), calc("1500", "21.06", "100").interest_this_month, "26.325: half up, not to even"
  end

  test "a payment at or below the monthly interest never pays off, without looping" do
    s = calc("5000", "22", "91.67").schedule
    assert s.never_pays_off
    assert_nil s.months
    assert_nil s.total_interest
    assert_empty s.balances, "stops in the first month, not at the 50-year cap"
    w = calc("5000", "22", "90").what_if(50)
    assert w[:schedule].months.positive?, "$140 does pay it off"
    assert_nil w[:interest_saved], "nothing to compare with a debt that never ends"
  end

  test "a payment that would take more than 50 years counts as never" do
    assert calc("100000", "10", "833.40").schedule.never_pays_off, "interest 833.33: 3 cents a month of principal"
  end

  test "a zero balance is already paid off; bad inputs raise" do
    s = calc("0", "20", "50").schedule
    assert_equal [0, BigDecimal("0"), false], [s.months, s.total_interest, s.never_pays_off]
    assert_raises(ArgumentError) { calc("10", "5", "0") }
    assert_raises(ArgumentError) { calc("-1", "5", "10") }
  end
end
