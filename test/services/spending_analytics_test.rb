require "test_helper"

# AN1: hand-calculated figures for the history in test/support/spending_scenario.rb.
class SpendingAnalyticsTest < ActiveSupport::TestCase
  include SpendingScenario

  setup do
    build_spending_scenario
    travel_to NOW
  end

  teardown { travel_back }

  def d(s) = Date.parse(s)
  def b(s) = BigDecimal(s)

  test "summary for Nov 1-26: refunds net, transfers, future rows and archived accounts left out" do
    s = SpendingAnalytics.summary(@user, from: d("2026-11-01"), to: d("2026-11-26"))
    # rent 1200 + 12, groceries 150 - 30, dining 40, personal care 25, uncategorized 18
    assert_equal b("1415"), s[:total_spent]
    assert_equal b("3001"), s[:total_income], "3000 pay + 1 interest; the +500 uncategorized isn't income"
    assert_equal [["rent", b("1212")], ["groceries", b("120")], ["dining-out", b("40")], ["personal-care", b("25")]],
                 s[:categories].map { |l| [l[:category], l[:spent]] }
    assert_equal b("18"), s[:uncategorized], "money out only: the +500 doesn't cancel it"
    assert_equal 10, s[:transaction_count]
    assert_equal [d("2026-08-01"), d("2026-11-20")], s.values_at(:data_from, :data_through)
    assert_equal "Your data runs through 2026-11-20.", s[:coverage_note]
  end

  test "a range that splits a transfer pair counts neither side" do
    # Nov 1-5 holds the -200 out (Nov 5) but not the +200 in (Nov 6)
    s = SpendingAnalytics.summary(@user, from: d("2026-11-01"), to: d("2026-11-05"))
    assert_equal [b("1350"), b("3000")], s.values_at(:total_spent, :total_income), "rent 1200 + groceries 150"
    s = SpendingAnalytics.summary(@user, from: d("2026-11-06"), to: d("2026-11-09"))
    assert_equal [b("0"), b("0"), 0], s.values_at(:total_spent, :total_income, :transaction_count)
  end

  test "the previous period has the same length, and the change is against it" do
    s = SpendingAnalytics.summary(@user, from: d("2026-11-01"), to: d("2026-11-26"))
    # Oct 6-31: groceries 420; dining's +20 refund alone floors at 0
    assert_equal({ from: d("2026-10-06"), to: d("2026-10-31"), total_spent: b("420"), total_income: b("0") }, s[:previous])
    assert_equal({ amount: b("995"), percent: b("236.9") }, s[:change])
  end

  test "summary for one category, and nothing before the data" do
    s = SpendingAnalytics.summary(@user, from: d("2026-10-01"), to: d("2026-10-31"), category: @dining)
    assert_equal [b("80"), b("0")], s.values_at(:total_spent, :uncategorized), "100 - 20 refund; the fixture coffee is uncategorized"
    early = SpendingAnalytics.summary(@user, from: d("2026-07-01"), to: d("2026-07-31"))
    assert_equal [b("0"), nil], [early[:total_spent], early[:change][:percent]]
    assert_equal "Your data starts on 2026-08-01.", early[:coverage_note]
  end

  test "more than 12 categories end in one Everything else line" do
    cats = (1..14).map { |i| Category.create!(name: "C#{i}", slug: "c#{i}", kind: "spending", fixed_variable: "variable", active: true, position: 100 + i) }
    cats.each_with_index { |c, i| @checking.transactions.create!(posted_on: d("2026-07-0#{(i % 9) + 1}"), amount: -(i + 1), description: "X#{i}", category: c, categorization_source: "rule") }
    s = SpendingAnalytics.summary(@user, from: d("2026-07-01"), to: d("2026-07-31"))
    assert_equal 13, s[:categories].size
    assert_equal({ category: nil, name: "Everything else", spent: b("3") }, s[:categories].last, "the two smallest: 1 + 2")
  end

  test "merchant_contains matches the normalized description" do
    @checking.transactions.create!(posted_on: d("2026-11-11"), amount: "-7.25", description: "Blue Bottle Coffee", category: @dining, categorization_source: "rule")
    s = SpendingAnalytics.summary(@user, from: d("2026-11-01"), to: d("2026-11-26"), merchant_contains: "bottle")
    assert_equal [b("7.25"), 1], s.values_at(:total_spent, :transaction_count)
  end

  test "range checks" do
    assert_raises(ArgumentError) { SpendingAnalytics.summary(@user, from: d("2026-11-02"), to: d("2026-11-01")) }
    assert_raises(ArgumentError) { SpendingAnalytics.summary(@user, from: d("2024-10-01"), to: d("2026-11-01")) }
  end

  test "budget vs actual for November: the budget in effect on the 1st, near and over" do
    r = SpendingAnalytics.budget_vs_actual(@user, month: d("2026-11-01"))
    assert_equal [["groceries", b("130"), b("120"), b("10"), "near"], ["dining-out", b("35"), b("40"), b("-5"), "over"],
                  ["entertainment", b("0"), b("0"), b("0"), "under"]],
                 r[:categories].map { |c| c.values_at(:category, :budget, :spent, :remaining, :status) }
    assert_equal({ budget: b("165"), spent: b("160"), remaining: b("5"), everyday_spent: b("203") }, r[:totals], "everyday: 160 + 25 unbudgeted + 18 uncategorized")
    assert_equal [{ category: "personal-care", name: "Personal Care", spent: b("25") }], r[:unbudgeted]
    assert_equal [b("18"), true, d("2026-11-20"), "2026-11"], r.values_at(:uncategorized, :plan_exists, :data_through, :month)
  end

  test "October uses October's budget; August has no plan" do
    oct = SpendingAnalytics.budget_vs_actual(@user, month: d("2026-10-01"))
    assert_equal [["groceries", b("400"), b("420"), b("-20"), "over"]], oct[:categories].map { |c| c.values_at(:category, :budget, :spent, :remaining, :status) }
    assert_equal [{ category: "dining-out", name: "Dining Out", spent: b("80") }], oct[:unbudgeted]
    assert_equal b("4.5"), oct[:uncategorized], "the fixture coffee"
    aug = SpendingAnalytics.budget_vs_actual(@user, month: d("2026-08-01"))
    assert_equal [false, []], aug.values_at(:plan_exists, :categories)
  end

  test "usual spending: median and mean over the full months the data covers" do
    r = SpendingAnalytics.category_averages(@user, months: 6)
    assert_equal %w[2026-10 2026-09 2026-08], r[:months_covered], "July is before the data, so not a $0 month"
    assert_equal [{ category: "groceries", name: "Groceries", mean: b("400"), median: b("400"), months: 3 },
                  { category: "dining-out", name: "Dining Out", mean: b("66.67"), median: b("70"), months: 3 }],
                 r[:categories], "groceries 400/380/420, dining 50/70/80; no spending → no line"
    assert_equal b("4.5"), r[:uncategorized_excluded]
  end

  test "a month the data doesn't reach isn't covered" do
    @savings.transactions.where(posted_on: d("2026-11-20")).delete_all # savings now ends Nov 6
    assert_equal %w[2026-10 2026-09 2026-08], SpendingAnalytics.category_averages(@user, months: 6)[:months_covered]
    @checking.transactions.where("posted_on > ?", d("2026-10-20")).delete_all # checking ends Oct 15
    assert_equal %w[2026-09 2026-08], SpendingAnalytics.category_averages(@user, months: 6)[:months_covered], "October isn't complete"
  end

  test "median of an even count is the average of the middle two" do
    assert_equal b("75"), SpendingAnalytics.median([b("50"), b("100"), b("70"), b("80")])
    assert_nil SpendingAnalytics.median([])
  end

  test "the change-a-budget context: weekly equivalent, 3-month average, spent this month" do
    r = SpendingAnalytics.category_context(@user, @groceries, amount: b("130"))
    assert_equal [b("30"), b("400"), 3, b("120"), "2026-11"], r.values_at(:weekly_equivalent, :average_last_3_months, :months_averaged, :spent_this_month, :month)
    assert_equal b("92"), SpendingAnalytics.category_context(@user, @groceries, amount: b("400"))[:weekly_equivalent], "400 × 12 / 52 = 92.31, down"
  end

  test "another user's rows never count" do
    other = users(:two).accounts.first
    other.transactions.create!(posted_on: d("2026-11-12"), amount: "-5000", description: "THEIRS", category: @groceries, categorization_source: "rule")
    assert_equal b("1415"), SpendingAnalytics.summary(@user, from: d("2026-11-01"), to: d("2026-11-26"))[:total_spent]
    assert_equal b("120"), SpendingAnalytics.budget_vs_actual(@user, month: d("2026-11-01"))[:categories].first[:spent]
  end
end
