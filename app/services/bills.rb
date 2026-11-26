# OB1 (bills): due dates with their paid status, for the Plan tab's Bills
# list, GET /obligations/due and (W1) Home's "Bills · next 7 days". All dates
# are the user's (UserClock).
module Bills
  Occurrence = Struct.new(:obligation, :due_on, :payment, keyword_init: true) do
    def paid? = payment.present?
    def paid_on = payment&.paid_on
  end

  WINDOW_DAYS = 7
  # Monthly equivalents for "Bills each month" (SCREENS_PLAN §4).
  PER_MONTH = { "weekly" => Rational(52, 12), "biweekly" => Rational(26, 12), "monthly" => 1, "yearly" => Rational(1, 12) }.freeze
  MONTHLY_TOTAL_ASSUMPTION = "Bills each month counts weekly bills as 52/12 a month, every-2-weeks bills as 26/12 " \
                             "and yearly bills as 1/12; one-off bills and bills that have ended aren't counted."

  module_function

  # Every due date of these obligations from `from` to `to`, with payments,
  # ordered by date then name.
  def occurrences(obligations, from:, to:)
    obligations = obligations.to_a
    payments = ObligationPayment.where(obligation_id: obligations.map(&:id), due_on: from..to)
                                .index_by { |p| [p.obligation_id, p.due_on] }
    obligations.flat_map do |ob|
      ob.schedule.between(from, to).map { |d| Occurrence.new(obligation: ob, due_on: d, payment: payments[[ob.id, d]]) }
    end.sort_by { |o| [o.due_on, o.obligation.name.downcase, o.obligation.id] }
  end

  # The occurrence a bill's status chip and Mark paid refer to:
  #   1. the earliest due date in the next 7 days (today … today + 6), else
  #   2. the latest due date before today, else
  #   3. the next one.
  # Status: paid / was_due (past, unpaid) / due_soon (in the 7 days) / due.
  def current(obligation, today:)
    schedule = obligation.schedule
    window_end = today + (WINDOW_DAYS - 1)
    due_on = schedule.between(today, window_end).first || schedule.last_before(today) || schedule.next_on_or_after(today)
    return nil if due_on.nil?

    payment = obligation.payments.find_by(due_on:)
    status =
      if payment then "paid"
      elsif due_on < today then "was_due"
      elsif due_on <= window_end then "due_soon"
      else "due"
      end
    { due_on:, status:, paid_on: payment&.paid_on }
  end

  # "Bills each month": the monthly equivalent of every active bill that
  # hasn't ended, to the cent.
  def monthly_total(obligations, today:)
    obligations.sum(BigDecimal("0")) do |ob|
      next 0 if ob.recurrence == "none" || (ob.ends_on && ob.ends_on < today)

      ob.amount * PER_MONTH.fetch(ob.recurrence) / ob.interval
    end.round(2)
  end
end
