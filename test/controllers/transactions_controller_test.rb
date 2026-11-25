require "test_helper"

# I2 (import endpoint): list, recategorize and delete the caller's transactions.
class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @groceries = Category.create!(name: "Groceries", slug: "t-groceries", kind: "spending",
                                  fixed_variable: "variable", active: true, position: 1)
    @transfers = Category.create!(name: "Transfers", slug: "t-transfers", kind: "transfer", active: true, position: 2)
    @legacy = categories(:expense)
    @mine = transactions(:one_coffee)
    @account = accounts(:one_checking)
    @nov = [
      @account.transactions.create!(posted_on: Date.new(2026, 11, 2), amount: "-64.18", description: "Grocer",
                                    category: @groceries, categorization_source: "rule"),
      @account.transactions.create!(posted_on: Date.new(2026, 11, 5), amount: "1500", description: "Paycheck",
                                    needs_review: true)
    ]
  end

  def list(**query)
    get api_v1_transactions_url(**query), headers: auth_headers, as: :json
    response.parsed_body
  end

  test "lists the caller's transactions, newest first, with money as strings" do
    body = list
    assert_response :success
    assert_equal [@nov[1].id, @nov[0].id, @mine.id], body["transactions"].map { |t| t["id"] }
    assert_equal 3, body["total"]
    assert_equal({ "amount" => "1500.00", "category" => nil, "needs_review" => true },
                 body["transactions"].first.slice("amount", "category", "needs_review"))
    assert_equal "-64.18", body["transactions"].second["amount"]
    assert_equal "t-groceries", body["transactions"].second["category"]
    assert_not_includes body["transactions"].first.keys, "base_key"
  end

  test "filters: account, dates, category, needs_review" do
    savings = users(:one).accounts.create!(name: "Savings", kind: "savings", purpose: "savings")
    other = savings.transactions.create!(posted_on: Date.new(2026, 11, 3), amount: "-1", description: "Fee")
    assert_equal [other.id], list(account_id: savings.id)["transactions"].map { |t| t["id"] }
    assert_equal [@nov[1].id, other.id, @nov[0].id], list(from: "2026-11-01")["transactions"].map { |t| t["id"] }
    assert_equal [@mine.id], list(to: "2026-10-31")["transactions"].map { |t| t["id"] }
    assert_equal [@nov[0].id], list(category: "t-groceries")["transactions"].map { |t| t["id"] }
    assert_equal 3, list(category: "none")["total"]
    assert_equal [@nov[1].id], list(needs_review: "true")["transactions"].map { |t| t["id"] }
  end

  test "bad filters are 422" do
    list(from: "11/01/2026")
    assert_response :unprocessable_entity
    assert_equal "from", response.parsed_body["field"]
    list(category: "no-such-slug")
    assert_response :unprocessable_entity
    list(category: @legacy.slug)
    assert_response :unprocessable_entity
  end

  test "pagination" do
    body = list(per_page: 2, page: 2)
    assert_equal [[@mine.id], 2, 2, 3], [body["transactions"].map { |t| t["id"] }, body["page"], body["per_page"], body["total"]]
    assert_equal 200, list(per_page: 10_000)["per_page"]
    assert_equal 1, list(page: -3)["page"]
  end

  test "PATCH sets the category as the user's choice and clears review" do
    patch api_v1_transaction_url(@nov[1]), params: { transaction: { category: "t-groceries" } }, headers: auth_headers, as: :json
    assert_response :success
    @nov[1].reload
    assert_equal [@groceries.id, "user", false], [@nov[1].category_id, @nov[1].categorization_source, @nov[1].needs_review]
  end

  test "PATCH with a null category makes the row uncategorized" do
    patch api_v1_transaction_url(@nov[0]), params: { transaction: { category: nil } }, headers: auth_headers, as: :json
    assert_response :success
    assert_equal [nil, "none"], @nov[0].reload.then { |t| [t.category_id, t.categorization_source] }
  end

  test "PATCH changes only the category" do
    patch api_v1_transaction_url(@nov[0]),
          params: { transaction: { category: "t-groceries", amount: "-1", posted_on: "2020-01-01", account_id: accounts(:two_checking).id } },
          headers: auth_headers, as: :json
    assert_response :success
    @nov[0].reload
    assert_equal [BigDecimal("-64.18"), Date.new(2026, 11, 2), @account.id], [@nov[0].amount, @nov[0].posted_on, @nov[0].account_id]
  end

  test "PATCH rejects unknown, legacy and Transfers categories, and a missing category key" do
    [["no-such-slug", "invalid_reference"], [@legacy.slug, "invalid_reference"], ["t-transfers", "transfer_category_reserved"]].each do |slug, code|
      patch api_v1_transaction_url(@nov[0]), params: { transaction: { category: slug } }, headers: auth_headers, as: :json
      assert_response :unprocessable_entity
      assert_equal code, response.parsed_body["error"], slug
    end
    patch api_v1_transaction_url(@nov[0]), params: { transaction: { amount: "-1" } }, headers: auth_headers, as: :json
    assert_equal "category_required", response.parsed_body["error"]
    assert_equal @groceries.id, @nov[0].reload.category_id
  end

  test "DELETE removes the caller's transaction" do
    assert_difference -> { Transaction.count }, -1 do
      delete api_v1_transaction_url(@nov[0]), headers: auth_headers, as: :json
    end
    assert_response :no_content
  end

  test "transactions in an archived account are read-only but still listed" do
    @account.archive!
    patch api_v1_transaction_url(@nov[0]), params: { transaction: { category: nil } }, headers: auth_headers, as: :json
    assert_response :unprocessable_entity
    delete api_v1_transaction_url(@nov[0]), headers: auth_headers, as: :json
    assert_response :unprocessable_entity
    assert_equal 3, list["total"]
  end
end
