require "test_helper"

# G2: goal progress, hand-calculated. "Today" is Thu 2026-11-26; the user's
# week starts on Monday unless set, so this week is Mon 11-23 … Sun 11-29.
class GoalCalculatorTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 26, 12)

  setup { @user = users(:one) }

  def goal(created_on, **attrs)
    @user.goals.create!({ goal_type: "upcoming_payment", name: "Car insurance", target_amount: "620",
                          target_date: Date.new(2027, 1, 10), created_at: created_on.to_time(:utc) + 12.hours }.merge(attrs))
  end

  def set_aside(g, on, amount) = travel_to(NOW) { g.contributions.create!(kind: "set_aside", amount:, contributed_on: on) }
  def balance(g, on, value) = travel_to(NOW) { g.contributions.create!(kind: "balance_update", balance_after: value, contributed_on: on) }
  def calc(g, **opts) = GoalCalculator.for(g.reload, now: NOW, **opts).call
  def d(s) = Date.parse(s)

  # Goal begun Mon 11-02, due Sun 2027-01-10 (week of Mon 01-04): 10 weeks,
  # $620 → $62 a week. Three weeks have passed by Mon 11-23.
  test "on track: weekly need is fixed for the week; milestones reached and projected" do
    g = goal(d("2026-11-02"))
    %w[2026-11-03 2026-11-10 2026-11-17].each { |day| set_aside(g, d(day), "62") }
    set_aside(g, d("2026-11-24"), "20")
    r = calc(g)
    assert_equal [BigDecimal("206"), BigDecimal("414"), 33], r.values_at(:saved, :remaining, :percent)
    assert_equal 7, r[:weeks_left], "11-23 through the week of 01-04"
    assert_equal BigDecimal("62"), r[:needed_per_week], "(620 - 186 at the week's start) / 7"
    assert_equal [BigDecimal("20"), BigDecimal("42")], r.values_at(:set_aside_this_week, :still_needed_this_week)
    assert r[:on_track], "206 ≥ 186 = 620 × 3/10"
    m = r[:milestones].to_h { |x| [x[:percent], x.values_at(:amount, :reached, :reached_on, :projected_on)] }
    assert_equal [BigDecimal("155"), true, d("2026-11-17"), nil], m[25]
    # from now: 206 + 42 = 248 by 11-29, then +62 a week: 310 by 12-06, 496 by 12-27, 620 by 01-10
    assert_equal [BigDecimal("310"), false, nil, d("2026-12-06")], m[50]
    assert_equal d("2026-12-27"), m[75].last
    assert_equal d("2027-01-10"), m[100].last
  end

  test "behind: only one week set aside, so the weekly need rises" do
    g = goal(d("2026-11-02"))
    set_aside(g, d("2026-11-03"), "62")
    r = calc(g)
    assert_equal BigDecimal("79.72"), r[:needed_per_week], "(620 - 62) / 7 = 79.714… rounded up"
    assert_equal false, r[:on_track], "62 < 186"
  end

  test "a goal begun this week is on track before anything is set aside" do
    r = calc(goal(d("2026-11-25")))
    assert r[:on_track]
    assert_equal BigDecimal("88.58"), r[:needed_per_week], "620 / 7 = 88.571… rounded up"
  end

  test "a mid-week target date: the last week's projection is the date itself, not the week's end" do
    r = calc(goal(d("2026-11-25"), target_date: d("2027-01-06"))) # Wednesday, week of Mon 01-04
    assert_equal 7, r[:weeks_left]
    assert_equal d("2027-01-06"), r[:milestones].last[:projected_on]
  end

  test "the user's own week start moves the weeks" do
    FinancialProfile.find_or_create_by!(user: @user).update!(week_starts_on: FinancialProfile::SUNDAY)
    g = goal(d("2026-11-02"), target_date: d("2027-01-09")) # a Saturday: the week of Sun 01-03
    set_aside(g, d("2026-11-22"), "10") # Sunday: this week now
    r = calc(g)
    assert_equal 7, r[:weeks_left], "Sun 11-22 through the week of Sun 01-03"
    assert_equal BigDecimal("10"), r[:set_aside_this_week]
    assert_equal BigDecimal("88.58"), r[:needed_per_week], "620 / 7, this week's 10 not deducted"
  end

  test "past the target date: everything left is needed now, behind, no projections" do
    g = goal(d("2026-10-01"), target_date: d("2026-11-15"))
    set_aside(g, d("2026-10-05"), "100")
    r = calc(g)
    assert_equal [0, BigDecimal("520"), false, true], r.values_at(:weeks_left, :needed_per_week, :on_track, :past_target_date)
    assert r[:milestones].reject { |m| m[:reached] }.all? { |m| m[:projected_on].nil? }
  end

  test "reached: on track and every milestone reached, even past the date" do
    g = goal(d("2026-10-01"), target_date: d("2026-11-15"))
    set_aside(g, d("2026-10-05"), "620")
    r = calc(g)
    assert_equal [BigDecimal("0"), 100, true], r.values_at(:remaining, :percent, :on_track)
    assert r[:milestones].all? { |m| m[:reached] && m[:reached_on] == d("2026-10-05") }
  end

  test "an undated purchase shows progress and milestones only" do
    g = goal(d("2026-11-02"), goal_type: "purchase", name: "Emergency fund", target_amount: "2000", target_date: nil, starting_balance: "500")
    set_aside(g, d("2026-11-10"), "100")
    r = calc(g)
    assert_equal [BigDecimal("600"), 30], r.values_at(:saved, :percent)
    assert_nil r[:weeks_left]
    assert_nil r[:needed_per_week]
    assert_nil r[:on_track]
    assert_equal [true, d("2026-11-02")], r[:milestones].first.values_at(:reached, :reached_on), "the starting $500 covers 25%"
    assert_nil r[:milestones][1][:projected_on]
    assert_includes r[:assumptions].join, "No target date"
  end

  # --- debt -------------------------------------------------------------------------

  def card(created_on, **attrs)
    goal(created_on, goal_type: "debt_payoff", name: "Card", target_amount: nil, target_date: nil,
                     starting_balance: "5000", apr: "22", monthly_payment: "200", **attrs)
  end

  test "debt: interest this month, payoff and the +$50 what-if (first payment next month)" do
    r = calc(card(d("2026-11-10")))
    assert_equal [BigDecimal("5000"), 0, BigDecimal("91.67")], r.values_at(:balance, :percent_paid, :interest_this_month)
    assert_equal({ never_pays_off: false, months: 34, payoff_month: "2029-09", total_interest: BigDecimal("1749.90") }, r[:payoff])
    assert_equal({ extra: BigDecimal("50"), never_pays_off: false, months: 26, payoff_month: "2029-01",
                   total_interest: BigDecimal("1285.71"), interest_saved: BigDecimal("464.19"), months_sooner: 8 }, r[:what_if])
    assert r[:on_track], "begun this month: no payment due yet"
    m25 = r[:milestones].first
    assert_equal [BigDecimal("1250"), false, d("2027-10-31")], m25.values_at(:amount, :reached, :projected_on), "payment 11 → Oct 2027"
    assert_includes r[:assumptions].join, "Fixed APR"
  end

  test "debt: the latest balance update drives everything; on track against scheduled payments" do
    g = card(d("2026-08-15"), starting_balance: "1840", apr: "22.9", monthly_payment: "120")
    # three payments since August: 1755.11, 1668.60, 1580.44
    balance(g, d("2026-11-20"), "1600")
    r = calc(g)
    assert_equal false, r[:on_track], "1600 > 1580.44"
    assert_equal 13, r[:percent_paid], "240 / 1840"
    balance(g, d("2026-11-25"), "1380")
    r = calc(g)
    assert r[:on_track]
    assert_equal [BigDecimal("1380"), 25], r.values_at(:balance, :percent_paid)
    assert_equal [true, d("2026-11-25")], r[:milestones].first.values_at(:reached, :reached_on), "1380 = 1840 × 0.75"
    # reference schedule from $1,380: 14 payments, $192.96 interest → Jan 2028
    assert_equal({ never_pays_off: false, months: 14, payoff_month: "2028-01", total_interest: BigDecimal("192.96") }, r[:payoff])
  end

  test "debt that never pays off: flagged, behind, no payoff month" do
    r = calc(card(d("2026-11-10"), monthly_payment: "90"))
    assert_equal({ never_pays_off: true, months: nil, payoff_month: nil, total_interest: nil }, r[:payoff])
    assert_equal false, r[:on_track]
    assert r[:what_if][:months].positive?
    assert r[:milestones].all? { |m| m[:projected_on].nil? }
  end
end
