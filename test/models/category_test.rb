require "test_helper"

# DM-1: database constraints and model rules for the flat category list.
class CategoryTest < ActiveSupport::TestCase
  def spending(**attrs)
    Category.new({ name: "Pets", slug: "pets", kind: "spending", active: true, fixed_variable: "variable" }.merge(attrs))
  end

  # Runs the block in its own savepoint and asserts the database itself
  # rejected it with the given PG error class, so one rejection can't
  # poison the rest of the test's transaction.
  def assert_db_rejects(pg_error, message = nil)
    error = assert_raises(ActiveRecord::StatementInvalid, message) do
      Category.transaction(requires_new: true) { yield }
    end
    assert_kind_of pg_error, error.cause, message
  end

  test "a valid spending category saves" do
    assert spending.save
  end

  test "kind must be known (model and database)" do
    assert_not spending(kind: "savings").valid?
    category = spending.tap(&:save!)
    assert_db_rejects(PG::CheckViolation) { category.update_columns(kind: "savings") }
  end

  test "new rows have no default kind" do
    assert_db_rejects(PG::NotNullViolation) do
      Category.insert_all!([{ name: "No kind", created_at: Time.current, updated_at: Time.current }])
    end
  end

  test "a spending category must be labelled fixed or variable (database check)" do
    assert_not spending(fixed_variable: nil).valid?
    category = spending.tap(&:save!)
    assert_db_rejects(PG::CheckViolation) { category.update_columns(fixed_variable: nil) }
  end

  test "labels only accept their allowed values (database checks)" do
    category = spending.tap(&:save!)
    { need_want: "maybe", fixed_variable: "sometimes", recurrence_label: "weekly" }.each do |column, value|
      assert_db_rejects(PG::CheckViolation, column.to_s) { category.update_columns(column => value) }
    end
  end

  test "every non-legacy category needs a slug (model and database)" do
    assert_not spending(slug: nil).valid?
    category = spending.tap(&:save!)
    assert_db_rejects(PG::CheckViolation) { category.update_columns(slug: nil) }
  end

  test "slugs are unique (database index)" do
    spending.save!
    assert_db_rejects(PG::UniqueViolation) do
      Category.insert_all!([{ name: "Dup", slug: "pets", kind: "spending", fixed_variable: "fixed", active: true,
                              created_at: Time.current, updated_at: Time.current }])
    end
  end

  test "legacy rows may have no slug or labels" do
    assert Category.new(name: "Old", kind: "legacy").valid?
  end
end
