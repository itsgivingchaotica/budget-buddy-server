require "test_helper"

# C2b (§B.2): recording a correction and undoing it.
class CategoryCorrectionsTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one_checking)
    @groceries = Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 1)
    @dining = Category.create!(name: "Dining Out", slug: "dining-out", kind: "spending", fixed_variable: "variable", active: true, position: 2)
    @picked = row("ZQX CORNER STORE #1", suggested_category: @dining)
    @other_a = row("ZQX CORNER STORE #2", suggested_category: @dining)
    @other_b = row("SQ *ZQX CORNER STORE")
  end

  def row(description, account: @account, needs_review: true, **attrs)
    @n = (@n || 0) + 1
    account.transactions.create!({ posted_on: Date.new(2026, 11, 3), amount: "-#{@n}.40", description:, needs_review: }.merge(attrs))
  end

  def pick(transaction, slug)
    patch api_v1_transaction_url(transaction), params: { transaction: { category: slug } }, headers: auth_headers, as: :json
    response.parsed_body
  end

  def undo(id)
    post undo_api_v1_category_correction_url(id), headers: auth_headers, as: :json
    response.parsed_body
  end

  test "a pick records a correction with every changed row and returns its id" do
    body = pick(@picked, "groceries")
    assert_equal 2, body["also_updated"]
    correction = CategoryCorrection.find(body["correction_id"])
    assert_equal [users(:one).id, @picked.id, @groceries.id, "ZQX CORNER STORE", nil],
                 [correction.user_id, correction.transaction_id, correction.new_category_id, correction.merchant_key, correction.merchant_rule_before]
    assert_equal [@picked.id, @other_a.id, @other_b.id].sort, correction.previous.map { |p| p["id"] }.sort
    assert_equal({ "id" => @picked.id, "category_id" => nil, "categorization_source" => "none", "confidence" => nil,
                   "needs_review" => true, "suggested_category_id" => @dining.id },
                 correction.previous.find { |p| p["id"] == @picked.id })
    assert_nil @other_a.reload.suggested_category_id, "categorizing clears the suggestion"
  end

  test "undo restores the group exactly, forgets the merchant, and reports the review count" do
    body = pick(@picked, "groceries")
    result = undo(body["correction_id"])
    assert_response :success
    assert_equal [@picked.id, @other_a.id, @other_b.id].sort, result["restored_transaction_ids"].sort
    [@picked, @other_a].each do |t|
      assert_equal [nil, "none", true, @dining.id], t.reload.then { |x| [x.category_id, x.categorization_source, x.needs_review, x.suggested_category_id] }
    end
    assert_equal [nil, true], @other_b.reload.then { |x| [x.category_id, x.needs_review] }
    assert_nil users(:one).merchant_rules.find_by(merchant_key: "ZQX CORNER STORE"), "the merchant isn't remembered any more"
    assert_equal Categorization::Review.remaining(users(:one)), result["remaining"]
  end

  test "after undo, a new row from that merchant goes back to review" do
    undo(pick(@picked, "groceries")["correction_id"])
    upload = Rack::Test::UploadedFile.new(StringIO.new("date,description,amount\n2026-12-09,ZQX CORNER STORE #77,-8.80\n"), "text/csv", original_filename: "d.csv")
    post api_v1_account_imports_url(@account), params: { file: upload }, headers: auth_headers
    assert_equal 0, response.parsed_body["categorized"]["memory"]
    assert @account.transactions.find_by(description: "ZQX CORNER STORE #77").needs_review
  end

  test "undo restores a merchant rule that existed before" do
    rule = users(:one).merchant_rules.create!(merchant_key: "ZQX CORNER STORE", category: @dining, hits: 4)
    undo(pick(@picked, "groceries")["correction_id"])
    assert_equal [@dining.id, 4], rule.reload.then { |r| [r.category_id, r.hits] }
  end

  test "undo leaves rows the user has changed since" do
    body = pick(@picked, "groceries")
    @other_a.reload.update!(category: @dining, categorization_source: "user")
    result = undo(body["correction_id"])
    assert_not_includes result["restored_transaction_ids"], @other_a.id
    assert_equal [@dining.id, "user"], @other_a.reload.then { |x| [x.category_id, x.categorization_source] }
  end

  test "a second undo is a 409" do
    id = pick(@picked, "groceries")["correction_id"]
    undo(id)
    undo(id)
    assert_response :conflict
    assert_equal "already_undone", response.parsed_body["error"]
  end

  test "deleting a corrected transaction also deletes its correction records" do
    id = pick(@other_b, "groceries")["correction_id"]
    delete api_v1_transaction_url(@other_b), headers: auth_headers, as: :json
    assert_response :no_content
    assert_not CategoryCorrection.exists?(id)
  end
end
