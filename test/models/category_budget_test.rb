require "test_helper"

# DM-3 (category budgets): the effective-from rule and validation.
class CategoryBudgetTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @groceries = Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 1)
    @dining = Category.create!(name: "Dining Out", slug: "dining-out", kind: "spending", fixed_variable: "variable", active: true, position: 2)
    @rent = Category.create!(name: "Rent", slug: "rent", kind: "spending", fixed_variable: "fixed", active: true, position: 3)
    @income = Category.create!(name: "Income", slug: "income", kind: "income", active: true, position: 4)
  end

  def budget(category, amount, month, user: @user)
    user.category_budgets.create!(category:, amount:, effective_from: month)
  end

  def in_effect(date) = CategoryBudget.in_effect_on(@user, date).to_h { |b| [b.category.slug, b.amount] }

  test "a March budget applies to April until a later row replaces it" do
    budget(@groceries, "400", Date.new(2026, 3, 1))
    assert_equal({ "groceries" => 400 }, in_effect(Date.new(2026, 4, 1)))
    budget(@groceries, "450", Date.new(2026, 5, 1))
    assert_equal({ "groceries" => 400 }, in_effect(Date.new(2026, 4, 1)), "April keeps March's amount")
    assert_equal({ "groceries" => 450 }, in_effect(Date.new(2026, 5, 1)))
    assert_equal({ "groceries" => 450 }, in_effect(Date.new(2026, 12, 1)))
    assert_equal({}, in_effect(Date.new(2026, 2, 1)), "nothing before the first row")
  end

  test "each category follows its own latest row" do
    budget(@groceries, "400", Date.new(2026, 1, 1))
    budget(@dining, "150", Date.new(2026, 4, 1))
    assert_equal({ "groceries" => 400 }, in_effect(Date.new(2026, 3, 1)))
    assert_equal({ "groceries" => 400, "dining-out" => 150 }, in_effect(Date.new(2026, 4, 1)))
  end

  test "another user's budgets are never in effect for me" do
    budget(@groceries, "999", Date.new(2026, 1, 1), user: users(:two))
    assert_equal({}, in_effect(Date.new(2026, 6, 1)))
  end

  test "only flexible categories have budgets" do
    assert_not @user.category_budgets.new(category: @rent, amount: 1, effective_from: Date.new(2026, 1, 1)).valid?, "fixed: a bill"
    assert_not @user.category_budgets.new(category: @income, amount: 1, effective_from: Date.new(2026, 1, 1)).valid?
    assert_not @user.category_budgets.new(category: categories(:expense), amount: 1, effective_from: Date.new(2026, 1, 1)).valid?
  end

  test "effective_from is the 1st, amounts aren't negative, one row per category and month (model and database)" do
    assert_not @user.category_budgets.new(category: @groceries, amount: 1, effective_from: Date.new(2026, 1, 2)).valid?
    assert_not @user.category_budgets.new(category: @groceries, amount: -1, effective_from: Date.new(2026, 1, 1)).valid?
    assert @user.category_budgets.new(category: @groceries, amount: 0, effective_from: Date.new(2026, 1, 1)).valid?, "0 = no budget"
    budget(@groceries, "400", Date.new(2026, 1, 1))
    assert_not @user.category_budgets.new(category: @groceries, amount: 5, effective_from: Date.new(2026, 1, 1)).valid?
    row = { user_id: @user.id, category_id: @groceries.id, amount: 5, created_at: Time.current, updated_at: Time.current }
    [[row.merge(effective_from: Date.new(2026, 2, 3)), PG::CheckViolation],
     [row.merge(effective_from: Date.new(2026, 2, 1), amount: -1), PG::CheckViolation],
     [row.merge(effective_from: Date.new(2026, 1, 1)), PG::UniqueViolation]].each do |attrs, error|
      e = assert_raises(ActiveRecord::StatementInvalid) { CategoryBudget.transaction(requires_new: true) { CategoryBudget.insert_all!([attrs]) } }
      assert_kind_of error, e.cause
    end
  end

  test "UserClock: this month is the user's own month, not UTC's" do
    FinancialProfile.find_or_create_by!(user: @user).update!(time_zone: "America/New_York")
    late_on_nov_30 = Time.utc(2026, 12, 1, 3, 0) # 22:00 on Nov 30 in New York
    assert_equal Date.new(2026, 11, 1), UserClock.month_start(@user, now: late_on_nov_30)
    assert_equal Date.new(2026, 12, 1), UserClock.month_start(users(:two), now: late_on_nov_30), "no zone set: UTC"
  end
end
