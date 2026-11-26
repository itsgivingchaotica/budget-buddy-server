require "test_helper"

# OB1 (bills): validation and database constraints.
class ObligationTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @rent = Category.create!(name: "Rent", slug: "rent", kind: "spending", fixed_variable: "fixed", active: true, position: 1)
    @groceries = Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 2)
  end

  def bill(**attrs)
    @user.obligations.new({ name: "Rent", amount: "1200", category: @rent, first_due_on: Date.new(2026, 12, 1), recurrence: "monthly" }.merge(attrs))
  end

  test "a monthly bill takes its day from the first due date" do
    ob = bill
    assert ob.save
    assert_equal 1, ob.day_of_month
    assert_nil bill(recurrence: "weekly", day_of_month: 5).tap(&:save!).day_of_month, "weekly bills have no day of month"
  end

  test "only fixed categories, positive amounts, known schedules" do
    assert_includes bill(category: @groceries).tap(&:valid?).errors[:category].join, "fixed"
    assert bill(amount: "0").invalid?
    assert bill(amount: "-5").invalid?
    assert bill(recurrence: "daily").invalid?
    assert bill(interval: 0).invalid?
    assert bill(name: "  ").invalid?
    assert bill(ends_on: Date.new(2026, 11, 1)).invalid?
  end

  test "the first due date must fall on the schedule's day" do
    assert bill(first_due_on: Date.new(2026, 11, 30), day_of_month: 31).valid?, "the 31st clamped to Nov 30"
    assert_includes bill(first_due_on: Date.new(2026, 11, 20), day_of_month: 31).tap(&:valid?).errors[:first_due_on].join, "day 31"
  end

  test "the paid-from account must be the user's own" do
    assert bill(account: accounts(:one_checking)).valid?
    assert_includes bill(account: accounts(:two_checking)).tap(&:valid?).errors[:account].join, "your accounts"
  end

  test "the database refuses what validation would" do
    ob = bill.tap(&:save!)
    [{ amount: 0 }, { recurrence: "daily" }, { interval: 0 }, { day_of_month: 32 }, { source: "bank" },
     { ends_on: Date.new(2026, 1, 1) }, { day_of_month: nil }].each do |attrs|
      assert_raises(ActiveRecord::StatementInvalid, attrs.inspect) do
        Obligation.transaction(requires_new: true) { ob.update_columns(attrs) }
      end
    end
  end

  test "payments: one per occurrence, a real due date, never paid in the future" do
    ob = bill.tap(&:save!)
    travel_to Time.utc(2026, 12, 3, 12) do
      assert ob.payments.create(due_on: Date.new(2026, 12, 1), paid_on: Date.new(2026, 12, 2)).persisted?
      assert_includes ob.payments.create(due_on: Date.new(2026, 12, 1), paid_on: Date.new(2026, 12, 2)).errors[:due_on].join, "taken"
      assert_includes ob.payments.create(due_on: Date.new(2026, 12, 2), paid_on: Date.new(2026, 12, 2)).errors[:due_on].join, "due date"
      assert_includes ob.payments.create(due_on: Date.new(2027, 1, 1), paid_on: Date.new(2026, 12, 4)).errors[:paid_on].join, "future"
      assert ob.payments.create(due_on: Date.new(2027, 1, 1), paid_on: Date.new(2026, 12, 3)).persisted?, "paying early is fine"
    end
    assert_raises(ActiveRecord::RecordNotUnique) do
      ObligationPayment.transaction(requires_new: true) { ObligationPayment.insert_all!([{ obligation_id: ob.id, due_on: Date.new(2026, 12, 1), paid_on: Date.new(2026, 12, 1) }]) }
    end
  end

  test "a bill with payments can't be deleted, only archived" do
    ob = bill(first_due_on: Date.new(2026, 1, 1)).tap(&:save!)
    ob.payments.create!(due_on: Date.new(2026, 1, 1), paid_on: Date.new(2026, 1, 1))
    assert_raises(ActiveRecord::InvalidForeignKey) { Obligation.transaction(requires_new: true) { Obligation.where(id: ob.id).delete_all } }
    ob.archive!
    assert ob.reload.archived?
    assert_equal 1, ob.payments.count
  end

  test "Bills.monthly_total counts monthly equivalents" do
    @user.obligations.create!(name: "Rent", amount: "1200", category: @rent, first_due_on: Date.new(2026, 1, 1), recurrence: "monthly")
    @user.obligations.create!(name: "Gym", amount: "10", category: @rent, first_due_on: Date.new(2026, 1, 2), recurrence: "weekly")
    @user.obligations.create!(name: "Car", amount: "600", category: @rent, first_due_on: Date.new(2026, 3, 1), recurrence: "yearly")
    @user.obligations.create!(name: "Water", amount: "90", category: @rent, first_due_on: Date.new(2026, 1, 5), recurrence: "monthly", interval: 3)
    @user.obligations.create!(name: "Once", amount: "500", category: @rent, first_due_on: Date.new(2026, 1, 5), recurrence: "none")
    @user.obligations.create!(name: "Ended", amount: "99", category: @rent, first_due_on: Date.new(2026, 1, 5), recurrence: "monthly", ends_on: Date.new(2026, 6, 5))
    # 1200 + 10 × 52/12 (43.333…) + 600/12 (50) + 90/3 (30) = 1323.33
    assert_equal BigDecimal("1323.33"), Bills.monthly_total(@user.obligations, today: Date.new(2026, 11, 26))
  end
end
