require "test_helper"

# T1 (transactions tables): model rules, database constraints and ownership.
class TransactionTest < ActiveSupport::TestCase
  setup do
    @groceries = Category.create!(name: "Groceries", slug: "t1-groceries", kind: "spending",
                                  fixed_variable: "variable", active: true, position: 1)
    @checking = accounts(:one_checking)
  end

  def txn(account: @checking, **attrs)
    account.transactions.new({ posted_on: Date.new(2026, 11, 2), amount: "-12.34",
                               description: "Trader Joe's #552" }.merge(attrs))
  end

  def assert_db_rejects(pg_error)
    error = assert_raises(ActiveRecord::StatementInvalid) { Transaction.transaction(requires_new: true) { yield } }
    assert_kind_of pg_error, error.cause
  end

  # Inserts with no model validation, so the database constraint is what's tested.
  def raw_insert(**attrs)
    t = txn.tap(&:valid?)
    row = t.attributes.except("id").merge("created_at" => Time.current, "updated_at" => Time.current)
    Transaction.insert_all!([row.merge(attrs.transform_keys(&:to_s))])
  end

  test "a valid transaction saves with derived keys" do
    t = txn.tap(&:save!)
    assert_equal "TRADER JOE'S", t.normalized_description
    assert_match(/\A[0-9a-f]{64}\z/, t.base_key)
    assert_equal 1, t.occurrence
    assert_equal "none", t.categorization_source
    assert_not t.needs_review
  end

  test "sign convention: negative is money out, positive is money in" do
    assert txn(amount: "-5.00").outflow?
    assert_not txn(amount: "-5.00").inflow?
    assert txn(amount: "1500.00").inflow?
    assert_not txn(amount: "1500.00").outflow?
  end

  test "zero amounts are rejected (model and database)" do
    assert_not txn(amount: 0).valid?
    assert_db_rejects(PG::CheckViolation) { raw_insert(amount: 0) }
  end

  test "amounts keep exact cents" do
    t = txn(amount: "-1234.56").tap(&:save!).reload
    assert_equal BigDecimal("-1234.56"), t.amount
  end

  test "description normalization strips store numbers and card fragments" do
    {
      "  target   #1234 " => "TARGET",
      "SHELL OIL 57444 XXXX1234" => "SHELL OIL",
      "Amazon Mktp ****9876" => "AMAZON MKTP",
      "STARBUCKS 08812" => "STARBUCKS",
      "Netflix.com" => "NETFLIX.COM",
      "7-ELEVEN" => "7-ELEVEN",
      "12345" => "12345"
    }.each { |raw, expected| assert_equal expected, Transaction.normalize_description(raw), raw }
  end

  test "base_key depends on date, amount in cents and normalized description" do
    key = ->(**a) { Transaction.base_key_for(**{ posted_on: Date.new(2026, 11, 2), amount: "-12.34", normalized_description: "X" }.merge(a)) }
    assert_equal key.call, key.call(amount: BigDecimal("-12.340"))
    assert_not_equal key.call, key.call(amount: "-12.35")
    assert_not_equal key.call, key.call(posted_on: Date.new(2026, 11, 3))
    assert_not_equal key.call, key.call(normalized_description: "Y")
    assert_equal txn(description: "trader joe's #9").tap(&:valid?).base_key, txn.tap(&:valid?).base_key
  end

  test "an identical row is a duplicate in the same account (model and database)" do
    txn.save!
    assert_not txn.valid?
    assert_db_rejects(PG::UniqueViolation) { raw_insert }
  end

  test "an identical row with the next occurrence number is allowed" do
    txn.save!
    assert txn(occurrence: 2).save
  end

  test "the same row in another account is not a duplicate" do
    txn.save!
    savings = users(:one).accounts.create!(name: "Savings", kind: "savings", purpose: "savings")
    assert txn(account: savings).save
    assert txn(account: accounts(:two_checking)).save
  end

  test "external_id is unique per account where present (model and database)" do
    txn(external_id: "BANK-1").save!
    assert_not txn(external_id: "BANK-1", amount: "-1.00").valid?
    assert_db_rejects(PG::UniqueViolation) { raw_insert(external_id: "BANK-1", amount: "-1.00", base_key: "a" * 64) }
    assert txn(account: accounts(:two_checking), external_id: "BANK-1").save
  end

  test "rows without external_id never collide on it (partial index)" do
    txn.save!
    assert txn(amount: "-1.00").save
    assert_equal 2, @checking.transactions.where(external_id: nil, posted_on: Date.new(2026, 11, 2)).count
  end

  test "rows with a bank id are keyed on it: different ids with identical content are both kept" do
    assert txn(external_id: "BANK-1").save
    assert txn(external_id: "BANK-2").save
    assert txn.save, "a row without an id is keyed on content, separately"
    assert_not txn(external_id: "BANK-1", amount: "-99.00").valid?
  end

  test "normalized descriptions are capped at 255 characters" do
    t = txn(description: "ß" * 255).tap(&:save!)
    assert_equal 255, t.normalized_description.length
  end

  test "categorization source and category must agree (model and database)" do
    assert_not txn(categorization_source: "ai").valid?
    assert_not txn(category: @groceries).valid?
    assert txn(category: @groceries, categorization_source: "rule").valid?
    assert_db_rejects(PG::CheckViolation) { raw_insert(categorization_source: "ai") }
    assert_db_rejects(PG::CheckViolation) { raw_insert(category_id: @groceries.id) }
  end

  test "unknown categorization source is rejected (model and database)" do
    assert_not txn(categorization_source: "magic").valid?
    assert_db_rejects(PG::CheckViolation) { raw_insert(categorization_source: "magic") }
  end

  test "legacy categories can't be assigned" do
    assert_not txn(category: categories(:expense), categorization_source: "user").valid?
  end

  test "confidence must be between 0 and 1 (model and database)" do
    assert_not txn(confidence: 1.5).valid?
    assert txn(confidence: 0.875).valid?
    assert_db_rejects(PG::CheckViolation) { raw_insert(confidence: 1.5) }
  end

  test "base_key must be a SHA-256 hex digest (database)" do
    assert_db_rejects(PG::CheckViolation) { raw_insert(base_key: "not-a-hash") }
  end

  test "an import from another account can't be attached (model and database)" do
    other_import = accounts(:two_checking).imports.create!(filename: "two.csv")
    assert_not txn(import: other_import).valid?
    assert_db_rejects(PG::ForeignKeyViolation) { raw_insert(import_id: other_import.id) }
    own_import = @checking.imports.create!(filename: "one.csv")
    assert txn(import: own_import).save
  end

  test "manual transactions have no import" do
    assert txn(import: nil).save
  end

  test "users reach only their own transactions" do
    mine = txn.tap(&:save!)
    theirs = txn(account: accounts(:two_checking)).tap(&:save!)
    assert_includes users(:one).transactions, mine
    assert_not_includes users(:one).transactions, theirs
    assert_raises(ActiveRecord::RecordNotFound) { users(:one).transactions.find(theirs.id) }
  end

  test "an account with transactions can't be destroyed (archive instead)" do
    txn.save!
    assert_raises(ActiveRecord::DeleteRestrictionError) { @checking.destroy }
  end
end
