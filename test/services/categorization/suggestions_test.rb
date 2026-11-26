require "test_helper"

# C2b (§B.1): suggested_category_id, Claude's below-threshold pick.
class Categorization::SuggestionsTest < ActiveSupport::TestCase
  class FakeAi
    def initialize(&answer) = @answer = answer
    def categorize(items:, allowed_slugs:) = @answer.call(items)
  end

  setup do
    transactions(:one_coffee).destroy!
    @user = users(:one)
    @account = accounts(:one_checking)
    @cat = { "groceries" => "spending", "dining-out" => "spending", "other" => "spending", "transfers" => "transfer" }
           .each_with_index.to_h do |(slug, kind), i|
      [slug, Category.create!(name: slug.titleize, slug:, kind:, active: true, position: i + 1,
                              fixed_variable: (kind == "spending" ? "variable" : nil))]
    end
  end

  def txn(description, **attrs)
    @n = (@n || 0) + 1
    @account.transactions.create!({ posted_on: Date.new(2026, 11, 2), amount: "-#{@n}.10", description: }.merge(attrs))
  end

  def run_with(&answer)
    Categorization::Pipeline.call(user: @user, scope: @user.transactions, ai: FakeAi.new(&answer))
  end

  test "an unsure but valid pick becomes the suggestion; the row stays uncategorized and in review" do
    t = txn("ZQX BISTRO")
    run_with { |items| items.map { |i| { index: i[:index], category_slug: "dining-out", confidence: 0.45 } } }
    t.reload
    assert_equal [nil, @cat["dining-out"].id, true, "none"],
                 [t.category_id, t.suggested_category_id, t.needs_review, t.categorization_source]
  end

  test "a confident pick categorizes with no suggestion" do
    t = txn("ZQX BISTRO")
    run_with { |items| items.map { |i| { index: i[:index], category_slug: "dining-out", confidence: 0.9 } } }
    assert_equal [@cat["dining-out"].id, nil], t.reload.then { |x| [x.category_id, x.suggested_category_id] }
  end

  test "invented slugs, Transfers and out-of-range confidence never become suggestions" do
    a = txn("ZQX ONE")
    b = txn("ZQX TWO")
    c = txn("ZQX THREE")
    run_with do |items|
      [{ index: 0, category_slug: "yachts", confidence: 0.3 }, { index: 1, category_slug: "transfers", confidence: 0.3 },
       { index: 2, category_slug: "groceries", confidence: 7 }]
    end
    [a, b, c].each { |t| assert_nil t.reload.suggested_category_id, t.description }
  end

  test "setting a category clears the suggestion; the database refuses both at once" do
    t = txn("ZQX BISTRO", suggested_category: @cat["dining-out"], needs_review: true)
    t.update!(category: @cat["groceries"], categorization_source: "user", needs_review: false)
    assert_nil t.reload.suggested_category_id
    error = assert_raises(ActiveRecord::StatementInvalid) do
      Transaction.transaction(requires_new: true) do
        t.update_columns(suggested_category_id: @cat["other"].id)
      end
    end
    assert_kind_of PG::CheckViolation, error.cause
  end

  test "a suggestion must be an active category other than Transfers" do
    t = @account.transactions.new(posted_on: Date.new(2026, 11, 2), amount: "-1", description: "X", suggested_category: @cat["transfers"])
    assert_not t.valid?
    t.suggested_category = categories(:expense)
    assert_not t.valid?, "legacy categories aren't suggestions either"
  end

  test "merchant memory later categorizes the row and clears its suggestion" do
    t = txn("ZQX BISTRO", suggested_category: @cat["dining-out"], needs_review: true)
    @user.merchant_rules.create!(merchant_key: "ZQX BISTRO", category: @cat["groceries"])
    Categorization::Pipeline.call(user: @user, scope: @user.transactions, ai: FakeAi.new { [] })
    assert_equal [@cat["groceries"].id, nil, "memory"],
                 t.reload.then { |x| [x.category_id, x.suggested_category_id, x.categorization_source] }
  end
end
