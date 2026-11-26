# G2 (goal and debt maths), D-011: a debt's monthly schedule at a fixed
# payment. Plain arithmetic, BigDecimal, no database access.
#
# Assumptions (returned with every result, see ASSUMPTIONS):
#   - the APR stays fixed and interest compounds monthly at APR / 12;
#   - each month's interest is rounded to the cent (half up) and added
#     before that month's payment;
#   - no new charges; the same payment every month, the last one smaller;
#   - the first payment is next month.
# A payment that doesn't cover the first month's interest never pays the
# debt off (never_pays_off), and neither does one that takes longer than
# MAX_MONTHS; neither loops forever.
class DebtCalculator
  MAX_MONTHS = 600 # 50 years
  ASSUMPTIONS = [
    "Fixed APR, interest added monthly at APR ÷ 12 and rounded to the cent.",
    "No new charges, and the same payment every month (the last one smaller).",
    "The first payment is next month. Estimates, not your lender's figures."
  ].freeze

  Schedule = Data.define(:months, :total_interest, :never_pays_off, :balances) do
    # The balance after `n` payments (n = 0: today's balance is not stored here).
    def balance_after(n) = n.zero? ? nil : balances.fetch(n - 1, BigDecimal("0"))
  end

  attr_reader :balance, :apr, :payment

  def initialize(balance:, apr:, payment:)
    @balance = balance.to_d
    @apr = apr.to_d
    @payment = payment.to_d
    raise ArgumentError, "balance must be 0 or more" if @balance.negative?
    raise ArgumentError, "payment must be more than 0" unless @payment.positive?
  end

  # One month's interest on `amount`, to the cent. Computed as amount × APR
  # ÷ 1200 in one step: a stored rate (APR ÷ 12) is cut off after its digits,
  # so an exact half cent (1380 × 22.9 ÷ 1200 = 26.335) would round down.
  def monthly_interest(amount) = (amount * apr / 1200).round(2, BigDecimal::ROUND_HALF_UP)

  # This month's interest on today's balance.
  def interest_this_month = monthly_interest(balance)

  def schedule(extra: 0)
    pay = payment + extra.to_d
    b = balance
    total = BigDecimal("0")
    balances = []
    while b.positive?
      interest = monthly_interest(b)
      if pay <= interest || balances.size >= MAX_MONTHS
        return Schedule.new(months: nil, total_interest: nil, never_pays_off: true, balances:)
      end

      paid = [pay, b + interest].min
      b = b + interest - paid
      total += interest
      balances << b
    end
    Schedule.new(months: balances.size, total_interest: total, never_pays_off: false, balances:)
  end

  # Paying `extra` more each month: payoff, interest, and what it saves.
  def what_if(extra)
    base = schedule
    more = schedule(extra:)
    saved = base.never_pays_off || more.never_pays_off ? nil : base.total_interest - more.total_interest
    sooner = base.never_pays_off || more.never_pays_off ? nil : base.months - more.months
    { extra: extra.to_d, schedule: more, interest_saved: saved, months_sooner: sooner }
  end
end
