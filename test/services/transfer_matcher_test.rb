require "test_helper"

# TR1 (transfer matching): the matching rule (handoff #05 §A).
class TransferMatcherTest < ActiveSupport::TestCase
  setup do
    transactions(:one_coffee).destroy!
    @user = users(:one)
    @checking = accounts(:one_checking)
    @savings = @user.accounts.create!(name: "Savings", kind: "savings", purpose: "savings")
    @venmo = @user.accounts.create!(name: "Venmo", kind: "p2p", purpose: "side_income")
  end

  def txn(account, day, amount, description = "TRANSFER")
    @n = (@n || 0) + 1
    account.transactions.create!(posted_on: Date.new(2026, 11, day), amount:, description: "#{description} #{@n}A")
  end

  def match(from: Date.new(2026, 11, 1), to: Date.new(2026, 11, 30))
    TransferMatcher.call(user: @user, from:, to:)
  end

  def pairs = @user.transfer_links.order(:id).pluck(:outflow_transaction_id, :inflow_transaction_id)

  test "pairs equal and opposite amounts in different accounts, exactly 3 days apart" do
    out = txn(@checking, 10, "-300.00")
    inn = txn(@savings, 13, "300.00")
    assert_equal 1, match
    link = @user.transfer_links.sole
    assert_equal [out.id, inn.id, "suggested", 3], [link.outflow_transaction_id, link.inflow_transaction_id, link.status, link.days_apart]
  end

  test "the inflow may come before the outflow" do
    out = txn(@checking, 12, "-50.00")
    inn = txn(@savings, 10, "50.00")
    match
    assert_equal [[out.id, inn.id]], pairs
  end

  test "4 days apart is not a transfer" do
    txn(@checking, 10, "-300.00")
    txn(@savings, 14, "300.00")
    assert_equal 0, match
  end

  test "same account never pairs" do
    txn(@checking, 10, "-300.00")
    txn(@checking, 11, "300.00")
    assert_equal 0, match
  end

  test "same sign never pairs" do
    txn(@checking, 10, "-300.00")
    txn(@savings, 11, "-300.00")
    assert_equal 0, match
  end

  test "different amounts never pair" do
    txn(@checking, 10, "-300.00")
    txn(@venmo, 11, "299.99")
    assert_equal 0, match
  end

  test "smallest gap wins when a row has several candidates" do
    out = txn(@checking, 10, "-100.00")
    far = txn(@savings, 12, "100.00")
    near = txn(@venmo, 11, "100.00")
    match
    assert_equal [[out.id, near.id]], pairs
    assert_not @user.transfer_links.exists?(inflow_transaction_id: far.id)
  end

  test "on equal gaps the earliest date wins, then the lowest id" do
    out = txn(@checking, 10, "-100.00")
    later = txn(@savings, 11, "100.00")
    earlier = txn(@venmo, 9, "100.00")
    match
    assert_equal [[out.id, earlier.id]], pairs, "same gap (1 day): the earlier candidate"

    out2 = txn(@checking, 20, "-70.00")
    first = txn(@savings, 21, "70.00")
    second = txn(@venmo, 21, "70.00")
    match
    assert_includes pairs, [out2.id, first.id], "same gap and date: the lowest id"
    assert_not @user.transfer_links.exists?(inflow_transaction_id: second.id)
    assert later.persisted?
  end

  test "each row is in at most one suggested or confirmed link" do
    a = txn(@checking, 10, "-40.00")
    b = txn(@venmo, 10, "-40.00")
    inn = txn(@savings, 11, "40.00")
    match
    assert_equal 1, @user.transfer_links.where(inflow_transaction_id: inn.id).count
    assert_equal [a.id], @user.transfer_links.pluck(:outflow_transaction_id), "lowest id on a tie"
    assert b.persisted?
  end

  test "running twice creates nothing new (idempotent)" do
    txn(@checking, 10, "-300.00")
    txn(@savings, 11, "300.00")
    assert_equal 1, match
    assert_equal 0, match
    assert_equal 1, @user.transfer_links.count
  end

  test "a rejected pair is never suggested again, but its rows can pair with others" do
    out = txn(@checking, 10, "-300.00")
    inn = txn(@savings, 11, "300.00")
    match
    @user.transfer_links.sole.update!(status: "rejected", rejected_at: Time.current)
    assert_equal 0, match
    other = txn(@venmo, 12, "300.00")
    assert_equal 1, match
    assert_equal [out.id, other.id], @user.transfer_links.find_by(status: "suggested").then { |l| [l.outflow_transaction_id, l.inflow_transaction_id] }
    assert inn.persisted?
  end

  test "rows in a confirmed link are not matched again" do
    out = txn(@checking, 10, "-300.00")
    txn(@savings, 11, "300.00")
    match
    @user.transfer_links.sole.update!(status: "confirmed", confirmed_at: Time.current)
    txn(@venmo, 12, "300.00")
    assert_equal 0, match
    assert_equal 1, @user.transfer_links.where(outflow_transaction_id: out.id).count
  end

  test "categorized rows are candidates too (e.g. a same-amount purchase, for the user to reject)" do
    groceries = Category.create!(name: "Groceries", slug: "t1-groceries", kind: "spending", fixed_variable: "variable",
                                 active: true, position: 1)
    @checking.transactions.create!(posted_on: Date.new(2026, 11, 10), amount: "-45.50", description: "TICKETMASTER",
                                   category: groceries, categorization_source: "rule")
    txn(@venmo, 9, "45.50", "Payment from A. Rivera")
    assert_equal 1, match
  end

  test "only rows within 3 days of the imported range are considered" do
    txn(@checking, 1, "-20.00")
    txn(@savings, 2, "20.00")
    assert_equal 0, match(from: Date.new(2026, 11, 10), to: Date.new(2026, 11, 20)), "Nov 1-2 is outside Nov 7-23"
    assert_equal 0, match(from: Date.new(2026, 11, 5), to: Date.new(2026, 11, 20)), "window from Nov 2: Nov 1 is outside"
    assert_equal 1, match(from: Date.new(2026, 11, 4), to: Date.new(2026, 11, 20)), "window from Nov 1: both inside"
  end

  test "another user's rows are never matched" do
    txn(@checking, 10, "-300.00")
    accounts(:two_savings).transactions.create!(posted_on: Date.new(2026, 11, 11), amount: "300.00", description: "THEIRS")
    assert_equal 0, match
  end

  test "the database refuses a second active link for the same row" do
    out = txn(@checking, 10, "-300.00")
    inn = txn(@savings, 11, "300.00")
    other = txn(@venmo, 11, "300.00")
    @user.transfer_links.create!(outflow_transaction: out, inflow_transaction: inn, days_apart: 1)
    error = assert_raises(ActiveRecord::RecordNotUnique) do
      TransferLink.insert_all!([{ user_id: @user.id, outflow_transaction_id: out.id, inflow_transaction_id: other.id,
                                  status: "suggested", days_apart: 1, created_at: Time.current, updated_at: Time.current }])
    end
    assert_kind_of PG::UniqueViolation, error.cause
  end
end
