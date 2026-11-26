require "test_helper"

# T1 (transactions tables): imports keep counts and line + code errors only (AD13).
class ImportTest < ActiveSupport::TestCase
  def import(**attrs)
    accounts(:one_checking).imports.new({ filename: " nov.csv " }.merge(attrs))
  end

  def assert_db_rejects(pg_error)
    error = assert_raises(ActiveRecord::StatementInvalid) { Import.transaction(requires_new: true) { yield } }
    assert_kind_of pg_error, error.cause
  end

  test "a new import starts processing with zero counts and no errors" do
    i = import.tap(&:save!)
    assert_equal "nov.csv", i.filename
    assert_equal "processing", i.status
    assert_equal [0, 0, 0, 0], [i.row_count, i.inserted_count, i.duplicate_count, i.error_count]
    assert_equal [], i.row_errors
  end

  test "row errors may hold only a line number and an error code" do
    assert import(row_errors: [{ line: 7, code: "bad_date" }]).valid?
    assert_not import(row_errors: [{ line: 7, code: "bad_date", raw: "2026-13-01,COFFEE,-4.50" }]).valid?
    assert_not import(row_errors: [{ line: 0, code: "bad_date" }]).valid?
    assert_not import(row_errors: [{ line: 7, code: "Bad date: COFFEE" }]).valid?
    assert_not import(row_errors: { line: 7 }).valid?
  end

  test "status, counts and date range are checked (model and database)" do
    assert_not import(status: "done").valid?
    assert_not import(row_count: -1).valid?
    assert_not import(data_from: Date.new(2026, 11, 5), data_through: Date.new(2026, 11, 1)).valid?
    saved = import.tap(&:save!)
    assert_db_rejects(PG::CheckViolation) { saved.update_columns(status: "done") }
    assert_db_rejects(PG::CheckViolation) { saved.update_columns(error_count: -1) }
    assert_db_rejects(PG::CheckViolation) { saved.update_columns(row_errors: { line: 1 }) }
    assert_db_rejects(PG::CheckViolation) do
      saved.update_columns(data_from: Date.new(2026, 11, 5), data_through: Date.new(2026, 11, 1))
    end
  end

  test "users reach only imports into their own accounts" do
    mine = import.tap(&:save!)
    theirs = accounts(:two_checking).imports.create!(filename: "two.csv")
    assert_includes users(:one).imports, mine
    assert_not_includes users(:one).imports, theirs
  end
end
