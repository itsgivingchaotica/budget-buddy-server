require "test_helper"

# TR1 (transfer matching): list, confirm, reject and undo (handoff #05 §A).
class TransferLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @transfers = Category.create!(name: "Transfers", slug: "transfers", kind: "transfer", active: true, position: 99)
    @groceries = Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable",
                                  active: true, position: 1)
    @checking = accounts(:one_checking)
    @savings = users(:one).accounts.create!(name: "Rainy Day Savings", kind: "savings", purpose: "savings")
    @out = @checking.transactions.create!(posted_on: Date.new(2026, 11, 10), amount: "-300.00",
                                          description: "TRANSFER TO SAVINGS", needs_review: true)
    @in = @savings.transactions.create!(posted_on: Date.new(2026, 11, 11), amount: "300.00",
                                        description: "TRANSFER FROM CHECKING", needs_review: true)
    TransferMatcher.call(user: users(:one), from: Date.new(2026, 11, 10), to: Date.new(2026, 11, 11))
    @link = users(:one).transfer_links.sole
  end

  def act(verb, path)
    public_send(verb, path, headers: auth_headers, as: :json)
    response.parsed_body
  end

  test "lists suggested pairs with both sides and days apart" do
    body = act(:get, api_v1_transfer_links_url)
    assert_response :success
    assert_equal 1, body["total"]
    link = body["transfer_links"].first
    assert_equal [@link.id, "suggested", 1, "300.00"], link.values_at("id", "status", "days_apart", "amount")
    assert_equal({ "id" => @out.id, "account_id" => @checking.id, "account_name" => "Everyday Checking",
                   "posted_on" => "2026-11-10", "description" => "TRANSFER TO SAVINGS", "amount" => "-300.00" },
                 link["outflow"])
    assert_equal "Rainy Day Savings", link["inflow"]["account_name"]
  end

  test "an unknown status filter is 422" do
    act(:get, api_v1_transfer_links_url(status: "maybe"))
    assert_response :unprocessable_entity
  end

  test "confirm makes both rows Transfers, out of review, and remembers their previous state" do
    body = act(:post, confirm_api_v1_transfer_link_url(@link))
    assert_response :success
    assert_equal "confirmed", body["status"]
    [@out, @in].each do |t|
      t.reload
      assert_equal [@transfers.id, "transfer", false], [t.category_id, t.categorization_source, t.needs_review]
    end
    stored = @link.reload.previous_state[@out.id.to_s]
    assert_equal({ "category_id" => nil, "categorization_source" => "none", "needs_review" => true, "confidence" => nil,
                   "suggested_category_id" => nil }, stored)
  end

  test "confirm twice is a 409" do
    act(:post, confirm_api_v1_transfer_link_url(@link))
    act(:post, confirm_api_v1_transfer_link_url(@link))
    assert_response :conflict
  end

  test "undo a confirm restores both rows and the suggestion" do
    @out.update!(category: @groceries, categorization_source: "ai", confidence: 0.7, needs_review: false)
    act(:post, confirm_api_v1_transfer_link_url(@link))
    body = act(:delete, api_v1_transfer_link_url(@link))
    assert_response :success
    assert_equal "suggested", body["status"]
    assert_equal [@groceries.id, "ai", BigDecimal("0.7"), false],
                 @out.reload.then { |t| [t.category_id, t.categorization_source, t.confidence, t.needs_review] }
    assert_equal [nil, "none", true], @in.reload.then { |t| [t.category_id, t.categorization_source, t.needs_review] }
    assert_nil @link.reload.previous_state
  end

  test "reject keeps the rows in review, and matching never suggests the pair again" do
    body = act(:post, reject_api_v1_transfer_link_url(@link))
    assert_equal "rejected", body["status"]
    assert_equal [true, nil], @out.reload.then { |t| [t.needs_review, t.category_id] }
    assert_equal 0, TransferMatcher.call(user: users(:one), from: Date.new(2026, 11, 1), to: Date.new(2026, 11, 30))
    assert_equal 0, users(:one).transfer_links.where(status: "suggested").count
  end

  test "undo a reject goes back to suggested; undo with nothing to undo is a 409" do
    act(:post, reject_api_v1_transfer_link_url(@link))
    assert_equal "suggested", act(:delete, api_v1_transfer_link_url(@link))["status"]
    act(:delete, api_v1_transfer_link_url(@link))
    assert_response :conflict
  end

  test "undo a reject is a 409 when a row has since joined another pair" do
    act(:post, reject_api_v1_transfer_link_url(@link))
    venmo = users(:one).accounts.create!(name: "Venmo", kind: "p2p", purpose: "side_income")
    venmo.transactions.create!(posted_on: Date.new(2026, 11, 11), amount: "300.00", description: "VENMO IN")
    TransferMatcher.call(user: users(:one), from: Date.new(2026, 11, 10), to: Date.new(2026, 11, 11))
    act(:delete, api_v1_transfer_link_url(@link))
    assert_response :conflict
    assert_equal "row_in_another_transfer", response.parsed_body["error"]
  end

  test "Transfers can only be set by a confirm: PATCH still refuses it" do
    patch api_v1_transaction_url(@out), params: { transaction: { category: "transfers" } }, headers: auth_headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "transfer_category_reserved", response.parsed_body["error"]
  end

  test "a transaction in a transfer pair can't be deleted (422, nothing deleted)" do
    assert_no_difference -> { Transaction.count } do
      delete api_v1_transaction_url(@out), headers: auth_headers, as: :json
    end
    assert_response :unprocessable_entity
    assert_equal "in_transfer_link", response.parsed_body["error"]
  end

  test "a merchant correction doesn't sweep rows in a transfer pair (AI3)" do
    other = @checking.transactions.create!(posted_on: Date.new(2026, 11, 20), amount: "-300.00",
                                           description: "TRANSFER TO SAVINGS #2", needs_review: true)
    patch api_v1_transaction_url(other), params: { transaction: { category: "groceries" } }, headers: auth_headers, as: :json
    assert_response :success
    assert_equal 0, response.parsed_body["also_updated"]
    assert_nil @out.reload.category_id
  end

  test "importing both sides suggests the pair" do
    users(:one).transfer_links.destroy_all
    upload = ->(text, name) { Rack::Test::UploadedFile.new(StringIO.new(text), "text/csv", original_filename: name) }
    post api_v1_account_imports_url(@checking), params: { file: upload.("date,description,amount\n2026-12-01,TRANSFER TO SAVINGS,-125.00\n", "c.csv") }, headers: auth_headers
    post api_v1_account_imports_url(@savings), params: { file: upload.("date,description,amount\n2026-12-02,TRANSFER FROM CHECKING,125.00\n", "s.csv") }, headers: auth_headers
    assert_response :created
    assert_equal 1, users(:one).transfer_links.where(status: "suggested", days_apart: 1).count
  end
end
