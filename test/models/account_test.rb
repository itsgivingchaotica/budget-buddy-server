require "test_helper"

# DM-2 (accounts): model rules and database constraints.
class AccountTest < ActiveSupport::TestCase
  def account(**attrs)
    users(:one).accounts.new({ name: "Savings", kind: "savings", purpose: "savings" }.merge(attrs))
  end

  def assert_db_rejects(pg_error)
    error = assert_raises(ActiveRecord::StatementInvalid) { Account.transaction(requires_new: true) { yield } }
    assert_kind_of pg_error, error.cause
  end

  test "a valid account saves, with the name trimmed" do
    a = account(name: "  Savings  ").tap(&:save!)
    assert_equal "Savings", a.name
  end

  test "names are unique per user, ignoring case (model and database)" do
    assert_not account(name: "everyday checking").valid?
    assert_db_rejects(PG::UniqueViolation) do
      Account.insert_all!([{ user_id: users(:one).id, name: "EVERYDAY CHECKING", kind: "savings", purpose: "savings",
                             created_at: Time.current, updated_at: Time.current }])
    end
  end

  test "two users can use the same account name" do
    assert_equal accounts(:one_checking).name, accounts(:two_checking).name
  end

  test "kind and purpose must be known (model and database)" do
    assert_not account(kind: "brokerage").valid?
    assert_not account(purpose: "fun").valid?
    saved = account.tap(&:save!)
    assert_db_rejects(PG::CheckViolation) { saved.update_columns(kind: "brokerage") }
    assert_db_rejects(PG::CheckViolation) { saved.update_columns(purpose: "fun") }
  end

  test "blank or overlong names are rejected (model and database)" do
    assert_not account(name: "   ").valid?
    assert_not account(name: "x" * 61).valid?
    saved = account.tap(&:save!)
    assert_db_rejects(PG::CheckViolation) { saved.update_columns(name: "  ") }
  end

  test "an opening balance needs its date, and vice versa (database)" do
    saved = account.tap(&:save!)
    assert_db_rejects(PG::CheckViolation) { saved.update_columns(opening_balance: 100) }
    assert_db_rejects(PG::CheckViolation) { saved.update_columns(opening_balance_on: Date.new(2026, 11, 1)) }
    saved.update_columns(opening_balance: 100, opening_balance_on: Date.new(2026, 11, 1))
  end

  test "archive! keeps the row and sets archived_at once" do
    a = accounts(:one_checking)
    a.archive!
    first = a.reload.archived_at
    assert first
    a.archive!
    assert_equal first, a.reload.archived_at
    assert_not_includes users(:one).accounts.active, a
  end
end
