require "test_helper"

# The stand-in plan for phone checks: budgets from AN1's usual, two bills,
# a goal; development/test only; adds only what's missing.
class Demo::SamplePlanTest < ActiveSupport::TestCase
  include SpendingScenario

  setup do
    build_spending_scenario
    CategoryBudget.where(user: @user).delete_all
    travel_to NOW
  end

  teardown { travel_back }

  test "budgets = usual rounded up to $5; Rent in 2 days, Phone on the week's first day, a goal" do
    utilities = Category.create!(name: "Utilities", slug: "utilities", kind: "spending", fixed_variable: "fixed", active: true, position: 11)
    assert_equal({ budgets: 2, bills: 2, goals: 1 }, Demo::SamplePlan.call(user: @user, env: "development"))
    assert_equal({ "groceries" => BigDecimal("400"), "dining-out" => BigDecimal("70") },
                 @user.category_budgets.includes(:category).to_h { |b| [b.category.slug, b.amount] }, "medians 400 and 70")
    assert_equal [["Phone", Date.new(2026, 11, 23), utilities.id], ["Rent", Date.new(2026, 11, 28), @rent.id]],
                 @user.obligations.order(:name).pluck(:name, :first_due_on, :category_id)
    assert_equal Date.new(2027, 1, 21), @user.goals.sole.target_date
    o = WeeklyOutlook.call(@user, now: NOW)
    assert_equal [["Phone", true], ["Rent", false]], o[:bills_due][:items].map { |i| [i[:name], i[:overdue]] }
  end

  test "a category whose usual is $0 gets no budget" do
    @checking.transactions.create!(posted_on: Date.new(2026, 9, 5), amount: "-30", description: "ONE-OFF", category: @personal,
                                   categorization_source: "rule") # 1 of 3 months: median 0
    Demo::SamplePlan.call(user: @user, env: "test")
    assert_not @user.category_budgets.exists?(category: @personal)
  end

  test "safe to run twice; refused outside development and test" do
    Demo::SamplePlan.call(user: @user, env: "test")
    assert_equal({ budgets: 0, bills: 0, goals: 0 }, Demo::SamplePlan.call(user: @user, env: "test"))
    assert_raises(Demo::SamplePlan::Refused) { Demo::SamplePlan.call(user: @user, env: "production") }
  end
end
