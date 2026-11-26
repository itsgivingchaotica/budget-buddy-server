require "test_helper"

# OB1 (bills): due dates, hand-calculated.
class RecurrenceScheduleTest < ActiveSupport::TestCase
  def sched(first, recurrence, **opts) = RecurrenceSchedule.new(first_due_on: Date.parse(first), recurrence:, **opts)
  def dates(*s) = s.map { |d| Date.parse(d) }

  test "monthly on the 31st clamps to the month's end and returns to the 31st" do
    s = sched("2026-01-31", "monthly")
    assert_equal dates("2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31"),
                 s.between(Date.new(2026, 1, 1), Date.new(2026, 5, 31))
  end

  test "leap year: Jan 31 → Feb 29 in 2028" do
    assert_equal dates("2028-01-31", "2028-02-29", "2028-03-31"),
                 sched("2028-01-31", "monthly").between(Date.new(2028, 1, 1), Date.new(2028, 3, 31))
  end

  test "a day_of_month of 31 starting on Nov 30 lands on Dec 31 later" do
    s = sched("2026-11-30", "monthly", day_of_month: 31)
    assert s.consistent?
    assert_equal dates("2026-11-30", "2026-12-31", "2027-01-31", "2027-02-28"),
                 s.between(Date.new(2026, 11, 1), Date.new(2027, 2, 28))
    assert_not sched("2026-11-29", "monthly", day_of_month: 31).consistent?, "Nov 29 isn't the 31st clamped"
  end

  test "every 3 months on the 15th" do
    assert_equal dates("2026-02-15", "2026-05-15", "2026-08-15", "2026-11-15"),
                 sched("2026-02-15", "monthly", interval: 3).between(Date.new(2026, 1, 1), Date.new(2026, 12, 31))
  end

  test "weekly and biweekly from the start date" do
    assert_equal dates("2026-11-06", "2026-11-13", "2026-11-20", "2026-11-27"),
                 sched("2026-11-06", "weekly").between(Date.new(2026, 11, 1), Date.new(2026, 11, 30))
    assert_equal dates("2026-11-06", "2026-11-20", "2026-12-04"),
                 sched("2026-11-06", "biweekly").between(Date.new(2026, 11, 1), Date.new(2026, 12, 10))
    assert_equal dates("2026-11-03", "2026-12-01"), sched("2026-10-06", "biweekly", interval: 2).between(Date.new(2026, 11, 1), Date.new(2026, 12, 10)),
                 "every 4 weeks"
  end

  test "yearly on Feb 29 falls on Feb 28 outside leap years" do
    assert_equal dates("2028-02-29", "2029-02-28", "2030-02-28", "2031-02-28", "2032-02-29"),
                 sched("2028-02-29", "yearly").between(Date.new(2028, 1, 1), Date.new(2032, 12, 31))
  end

  test "none is one date; ends_on stops the schedule" do
    assert_equal dates("2026-12-05"), sched("2026-12-05", "none").between(Date.new(2026, 1, 1), Date.new(2027, 12, 31))
    s = sched("2026-01-10", "monthly", ends_on: Date.new(2026, 3, 10))
    assert_equal dates("2026-01-10", "2026-02-10", "2026-03-10"), s.between(Date.new(2026, 1, 1), Date.new(2026, 12, 31))
    assert_nil s.next_on_or_after(Date.new(2026, 3, 11))
  end

  test "nothing before the first due date, even when the range starts earlier" do
    assert_equal [], sched("2026-12-01", "weekly").between(Date.new(2026, 1, 1), Date.new(2026, 11, 30))
  end

  test "occurs_on?, last_before and next_on_or_after" do
    s = sched("2026-01-31", "monthly")
    assert s.occurs_on?(Date.new(2026, 2, 28))
    assert_not s.occurs_on?(Date.new(2026, 2, 27))
    assert_not s.occurs_on?(Date.new(2025, 12, 31)), "before the first date"
    assert_equal Date.new(2026, 2, 28), s.last_before(Date.new(2026, 3, 31))
    assert_equal Date.new(2026, 3, 31), s.last_before(Date.new(2026, 4, 1))
    assert_nil s.last_before(Date.new(2026, 1, 31))
    assert_equal Date.new(2026, 3, 31), s.next_on_or_after(Date.new(2026, 3, 1))
    assert_equal Date.new(2026, 1, 31), s.next_on_or_after(Date.new(2020, 1, 1))
    w = sched("2026-11-06", "weekly")
    assert_equal Date.new(2027, 11, 5), w.next_on_or_after(Date.new(2027, 11, 1)), "a year later: 52 weeks on"
    assert_equal Date.new(2027, 10, 29), w.last_before(Date.new(2027, 11, 5))
  end

  test "bad input raises" do
    assert_raises(ArgumentError) { sched("2026-01-01", "daily") }
    assert_raises(ArgumentError) { sched("2026-01-01", "weekly", interval: 0) }
  end
end
