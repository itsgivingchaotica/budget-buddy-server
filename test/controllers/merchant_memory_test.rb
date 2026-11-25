require "test_helper"
require "minitest/mock"

# AI3 (learning from corrections): a user's recategorization becomes merchant
# memory, and the next import of that merchant uses it with no AI call.
class MerchantMemoryTest < ActionDispatch::IntegrationTest
  class FakeAi
    attr_reader :calls

    def initialize = @calls = []
    def categorize(items:, allowed_slugs:) = (@calls << items) && []
  end

  setup do
    @account = accounts(:one_checking)
    @groceries = Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 1)
    @dining = Category.create!(name: "Dining Out", slug: "dining-out", kind: "spending", fixed_variable: "variable", active: true, position: 2)
    @row = @account.transactions.create!(posted_on: Date.new(2026, 11, 2), amount: "-18.40",
                                         description: "SQ *ZQX Corner Store #12", needs_review: true)
  end

  def recategorize(transaction, slug)
    patch api_v1_transaction_url(transaction), params: { transaction: { category: slug } }, headers: auth_headers, as: :json
  end

  def import_csv(text)
    upload = Rack::Test::UploadedFile.new(StringIO.new(text), "text/csv", original_filename: "dec.csv")
    post api_v1_account_imports_url(@account), params: { file: upload }, headers: auth_headers
    response.parsed_body
  end

  test "recategorizing saves a merchant rule for the caller" do
    assert_difference -> { users(:one).merchant_rules.count }, 1 do
      recategorize(@row, "groceries")
    end
    assert_response :success
    rule = users(:one).merchant_rules.last
    assert_equal ["ZQX CORNER STORE", @groceries.id, 0], [rule.merchant_key, rule.category_id, rule.hits]
  end

  test "the next import of that merchant uses memory, with no AI call" do
    recategorize(@row, "groceries")
    ai = FakeAi.new
    Categorization::DisabledAi.stub(:new, ai) do
      body = import_csv("date,description,amount\n2026-12-03,ZQX CORNER STORE #99,-7.10\n2026-12-04,Unknown Thing,-3.00\n")
      assert_equal({ "memory" => 1, "rule" => 0, "ai" => 0, "needs_review" => 1 }, body["categorized"].slice("memory", "rule", "ai", "needs_review"))
    end
    learned = @account.transactions.find_by(posted_on: Date.new(2026, 12, 3))
    assert_equal [@groceries.id, "memory"], [learned.category_id, learned.categorization_source]
    assert_equal [["UNKNOWN THING"]], ai.calls.map { |items| items.map { |i| i[:merchant] } }
  end

  test "a new choice replaces the old rule and restarts its hit count; the same choice keeps it" do
    recategorize(@row, "groceries")
    rule = users(:one).merchant_rules.find_by!(merchant_key: "ZQX CORNER STORE")
    rule.update_columns(hits: 5)

    recategorize(@row, "groceries")
    assert_equal [@groceries.id, 5], rule.reload.then { |r| [r.category_id, r.hits] }

    recategorize(@row, "dining-out")
    assert_equal [@dining.id, 0], rule.reload.then { |r| [r.category_id, r.hits] }
    assert_equal 1, users(:one).merchant_rules.where(merchant_key: "ZQX CORNER STORE").count
  end

  test "clearing a category doesn't change memory" do
    recategorize(@row, "groceries")
    assert_no_changes -> { users(:one).merchant_rules.pluck(:merchant_key, :category_id) } do
      recategorize(@row, nil)
    end
  end

  test "refused changes teach nothing" do
    Category.create!(name: "Transfers", slug: "transfers", kind: "transfer", active: true, position: 3)
    assert_no_difference -> { MerchantRule.count } do
      recategorize(@row, "transfers")
      recategorize(@row, "no-such-slug")
      recategorize(transactions(:two_coffee), "groceries")
    end
  end

  test "memory is per user" do
    recategorize(@row, "groceries")
    assert_equal 0, users(:two).merchant_rules.count
    summary = Categorization::Pipeline.call(user: users(:two), scope: users(:two).transactions)
    assert_equal 0, summary.memory
  end

  # Store numbers are stripped from keys, so each row gets its own amount.
  def row(description, account: @account, **attrs)
    @n = (@n || 0) + 1
    account.transactions.create!({ posted_on: Date.new(2026, 11, 9), amount: "-#{@n}.25", description: }.merge(attrs))
  end

  test "clearing a row categorized from memory forgets that merchant rule" do
    recategorize(@row, "groceries")
    from_memory = row("ZQX CORNER STORE #40", category: @groceries, categorization_source: "memory")
    assert_difference -> { users(:one).merchant_rules.count }, -1 do
      recategorize(from_memory, nil)
    end
    assert_response :success
    assert_nil users(:one).merchant_rules.find_by(merchant_key: "ZQX CORNER STORE")
    assert from_memory.reload.needs_review
  end

  test "clearing a row from rules, AI or the user leaves memory alone" do
    recategorize(@row, "groceries")
    %w[rule user].each do |source|
      t = row("ZQX CORNER STORE #4#{source.size}", category: @groceries, categorization_source: source)
      assert_no_difference -> { MerchantRule.count } do
        recategorize(t, nil)
      end
    end
    ai_row = row("ZQX CORNER STORE #77", category: @groceries, categorization_source: "ai", confidence: 0.9)
    assert_no_difference -> { MerchantRule.count } do
      recategorize(ai_row, nil)
    end
  end

  test "another user's memory for the same merchant isn't forgotten" do
    users(:two).merchant_rules.create!(merchant_key: "ZQX CORNER STORE", category: @groceries)
    from_memory = row("ZQX CORNER STORE", category: @groceries, categorization_source: "memory")
    recategorize(from_memory, nil)
    assert users(:two).merchant_rules.exists?(merchant_key: "ZQX CORNER STORE")
  end

  test "a correction also updates the user's other rows from that merchant waiting for review" do
    waiting = [row("ZQX Corner Store #1", needs_review: true), row("TST* ZQX CORNER STORE", needs_review: true)]
    mine = row("ZQX CORNER STORE #2", category: @dining, categorization_source: "user", needs_review: true)
    not_waiting = row("ZQX CORNER STORE #3")
    other_merchant = row("SOMEWHERE ELSE", needs_review: true)
    theirs = row("ZQX CORNER STORE", account: accounts(:two_checking), needs_review: true)
    archived = users(:one).accounts.create!(name: "Old card", kind: "credit_card", purpose: "spending")
    in_archived = row("ZQX CORNER STORE", account: archived, needs_review: true)
    archived.archive!

    recategorize(@row, "groceries")
    assert_response :success
    assert_equal 2, response.parsed_body["also_updated"]
    waiting.each do |t|
      assert_equal [@groceries.id, "memory", false], t.reload.then { |x| [x.category_id, x.categorization_source, x.needs_review] }
    end
    assert_equal [@dining.id, "user"], mine.reload.then { |x| [x.category_id, x.categorization_source] }
    assert_equal [nil, false], not_waiting.reload.then { |x| [x.category_id, x.needs_review] }
    assert other_merchant.reload.needs_review
    assert_equal [nil, true], theirs.reload.then { |x| [x.category_id, x.needs_review] }
    assert_equal [nil, true], in_archived.reload.then { |x| [x.category_id, x.needs_review] }
  end

  test "also_updated is 0 when nothing else is waiting" do
    recategorize(@row, "groceries")
    assert_equal 0, response.parsed_body["also_updated"]
  end

  test "the correction, memory and waiting rows are saved together or not at all" do
    waiting = row("ZQX Corner Store #1", needs_review: true)
    MerchantRule.stub(:upsert, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      assert_raises(ActiveRecord::StatementInvalid) { recategorize(@row, "groceries") }
    end
    assert_equal [nil, true], @row.reload.then { |x| [x.category_id, x.needs_review] }
    assert_nil waiting.reload.category_id
  end
end
