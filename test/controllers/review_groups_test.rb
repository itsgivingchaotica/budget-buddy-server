require "test_helper"

# C2b (§B.3): GET /transactions/review_groups.
class ReviewGroupsTest < ActionDispatch::IntegrationTest
  setup do
    transactions(:one_coffee).destroy!
    @checking = accounts(:one_checking)
    @savings = users(:one).accounts.create!(name: "Rainy Day Savings", kind: "savings", purpose: "savings")
    cats = %w[groceries dining-out entertainment other income].each_with_index.to_h do |slug, i|
      kind = slug == "income" ? "income" : "spending"
      [slug, Category.create!(name: slug.titleize, slug:, kind:, active: true, position: i + 1,
                              fixed_variable: (kind == "spending" ? "variable" : nil))]
    end
    @cat = cats
  end

  def row(description, amount, day, account: @checking, **attrs)
    account.transactions.create!({ posted_on: Date.new(2026, 11, day), amount:, description:, needs_review: true }.merge(attrs))
  end

  def groups
    get review_groups_api_v1_transactions_url, headers: auth_headers, as: :json
    assert_response :success
    response.parsed_body
  end

  test "groups waiting rows by merchant with count, total, accounts, latest row, suggestion and alternatives" do
    row("SQ *HARBOR BEAN", "-6.75", 1, suggested_category: @cat["dining-out"])
    row("HARBOR BEAN", "-5.25", 3, suggested_category: @cat["dining-out"])
    latest = row("HARBOR BEAN #2", "-4.00", 5)
    # Usage the alternatives are drawn from (money out): groceries x2, entertainment x1.
    row("A", "-1.00", 9, needs_review: false, category: @cat["groceries"], categorization_source: "rule")
    row("B", "-2.00", 9, needs_review: false, category: @cat["groceries"], categorization_source: "rule")
    row("C", "-3.00", 9, needs_review: false, category: @cat["entertainment"], categorization_source: "rule")

    body = groups
    assert_equal 3, body["remaining"]
    group = body["groups"].sole
    assert_equal({ "merchant_key" => "HARBOR BEAN", "display_name" => "HARBOR BEAN #2", "count" => 3, "total" => "-16.00",
                   "accounts" => [{ "id" => @checking.id, "name" => "Everyday Checking", "purpose" => "spending" }],
                   "representative_transaction_id" => latest.id,
                   "suggested_category" => { "id" => @cat["dining-out"].id, "slug" => "dining-out", "name" => "Dining Out" },
                   "alternatives" => [{ "id" => @cat["groceries"].id, "slug" => "groceries", "name" => "Groceries" },
                                      { "id" => @cat["entertainment"].id, "slug" => "entertainment", "name" => "Entertainment" }] },
                 group)
  end

  test "alternatives follow the direction of the money and fall back to Other" do
    row("PAYMENT FROM A. RIVERA", "80.00", 2)
    row("SALARY", "2000.00", 9, needs_review: false, category: @cat["income"], categorization_source: "rule")
    group = groups["groups"].sole
    assert_nil group["suggested_category"]
    assert_equal %w[income other], group["alternatives"].map { |c| c["slug"] }
  end

  test "rows in a suggested transfer pair are on Transfers, not Review" do
    out = row("TRANSFER TO SAVINGS", "-300.00", 10)
    inn = row("TRANSFER FROM CHECKING", "300.00", 11, account: @savings)
    users(:one).transfer_links.create!(outflow_transaction: out, inflow_transaction: inn, days_apart: 1)
    row("ZQX THING", "-9.00", 4)
    body = groups
    assert_equal ["ZQX THING"], body["groups"].map { |g| g["merchant_key"] }
    assert_equal 1, body["remaining"]
  end

  test "a transfer-like row with no pair still shows, never with a Transfers chip" do
    row("TRANSFER TO MOM", "-50.00", 4)
    group = groups["groups"].sole
    assert_not_includes group["alternatives"].map { |c| c["slug"] }, "transfers"
  end

  test "largest count first, then largest absolute total; archived accounts and other users' rows excluded" do
    row("SMALL ONE", "-1.00", 1)
    row("BIG ONE", "-500.00", 1)
    2.times { |i| row("TWICE ##{i + 1}", "-2.0#{i}", 2) }
    archived = users(:one).accounts.create!(name: "Old", kind: "checking", purpose: "spending")
    row("HIDDEN", "-1.00", 1, account: archived)
    archived.archive!
    row("THEIRS", "-1.00", 1, account: accounts(:two_checking))
    assert_equal ["TWICE", "BIG ONE", "SMALL ONE"], groups["groups"].map { |g| g["merchant_key"] }
  end

  test "picking a chip on the representative row clears the whole group" do
    row("HARBOR BEAN", "-5.25", 3)
    latest = row("HARBOR BEAN #2", "-4.00", 5)
    patch api_v1_transaction_url(latest), params: { transaction: { category: "dining-out" } }, headers: auth_headers, as: :json
    assert_equal 1, response.parsed_body["also_updated"]
    assert_equal 0, groups["remaining"]
  end
end
