# OB1 (bills), plan AD9: a bill's structured schedule → its due dates.
#
#   none      one occurrence, on first_due_on
#   weekly    every `interval` weeks from first_due_on
#   biweekly  every 2 × `interval` weeks from first_due_on
#   monthly   every `interval` months on day_of_month
#   yearly    every `interval` years, in first_due_on's month, on day_of_month
#
# Month-end clamping: a day_of_month of 29-31 falls on the month's last day
# when the month is shorter (Jan 31 → Feb 28, or Feb 29 in a leap year → Mar
# 31). Each occurrence is counted from first_due_on, never from the previous
# (clamped) one, so a bill on the 31st goes back to the 31st after February.
# Nothing falls after ends_on.
#
# Plain arithmetic, no database access.
class RecurrenceSchedule
  KINDS = %w[none weekly biweekly monthly yearly].freeze
  MONTHLY = %w[monthly yearly].freeze

  attr_reader :first_due_on, :recurrence, :interval, :day_of_month, :ends_on

  def self.for(obligation)
    new(first_due_on: obligation.first_due_on, recurrence: obligation.recurrence, interval: obligation.interval,
        day_of_month: obligation.day_of_month, ends_on: obligation.ends_on)
  end

  def initialize(first_due_on:, recurrence:, interval: 1, day_of_month: nil, ends_on: nil)
    raise ArgumentError, "unknown recurrence #{recurrence.inspect}" unless KINDS.include?(recurrence)
    raise ArgumentError, "interval must be at least 1" unless interval.is_a?(Integer) && interval >= 1

    @first_due_on = first_due_on
    @recurrence = recurrence
    @interval = interval
    @day_of_month = MONTHLY.include?(recurrence) ? (day_of_month || first_due_on.day) : nil
    @ends_on = ends_on
  end

  # Due dates from `from` to `to`, both included, in order.
  def between(from, to)
    dates = []
    n = estimate_index(from)
    loop do
      date = occurrence(n)
      break if date.nil? || date > to

      dates << date if date >= from
      n += 1
    end
    dates
  end

  def occurs_on?(date)
    between(date, date).any?
  end

  # The latest due date before `date` (nil if none).
  def last_before(date)
    n = estimate_index(date)
    n += 1 while (d = occurrence(n + 1)) && d < date
    n -= 1 while n >= 0 && (occurrence(n).nil? || occurrence(n) >= date)
    n >= 0 ? occurrence(n) : nil
  end

  # The earliest due date on or after `date` (nil if the schedule has ended).
  def next_on_or_after(date)
    n = estimate_index(date)
    n += 1 while (d = occurrence(n)) && d < date
    occurrence(n)
  end

  # Does first_due_on itself fall on the schedule? (For monthly/yearly, its
  # day must be day_of_month, clamped to that month's length.)
  def consistent?
    return true unless MONTHLY.include?(recurrence)

    first_due_on.day == [day_of_month, days_in_month(first_due_on.year, first_due_on.month)].min
  end

  private

  # The n-th due date (n = 0 is the first), or nil past the end.
  def occurrence(n)
    return nil if n.negative?

    date =
      case recurrence
      when "none" then n.zero? ? first_due_on : nil
      when "weekly" then first_due_on + (7 * interval * n)
      when "biweekly" then first_due_on + (14 * interval * n)
      when "monthly" then on_day(month_index(first_due_on) + (interval * n))
      when "yearly" then on_day(month_index(first_due_on) + (12 * interval * n))
      end
    return nil if date.nil? || (ends_on && date > ends_on)

    date
  end

  # An index that is never past the first due date on or after `date`.
  def estimate_index(date)
    return 0 if date <= first_due_on

    steps =
      case recurrence
      when "none" then 0
      when "weekly" then (date - first_due_on).to_i / (7 * interval)
      when "biweekly" then (date - first_due_on).to_i / (14 * interval)
      when "monthly" then (month_index(date) - month_index(first_due_on)) / interval
      when "yearly" then (month_index(date) - month_index(first_due_on)) / (12 * interval)
      end
    [steps - 1, 0].max
  end

  def month_index(date) = (date.year * 12) + date.month - 1

  def on_day(index)
    year, month0 = index.divmod(12)
    Date.new(year, month0 + 1, [day_of_month, days_in_month(year, month0 + 1)].min)
  end

  def days_in_month(year, month) = Date.new(year, month, -1).day
end
