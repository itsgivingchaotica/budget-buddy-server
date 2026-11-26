# G2 (goal and debt maths): a goal's progress, in the user's own weeks and
# months (UserClock). Read-only; BigDecimal throughout. The Plan tab (C8),
# Home's goal contributions (W1), plan drafts (PL1) and the coach (AS1) all
# use this, so their figures agree. Every result carries its assumptions.
#
# Saving goals (upcoming payment, purchase):
#   remaining           target - saved (never below 0)
#   weeks_left          the user's weeks from this one through the one holding
#                       target_date, both counted (0 once target_date has passed)
#   needed_per_week     what was still to save at the start of this week,
#                       spread evenly over weeks_left, rounded up to the cent.
#                       Fixed for the whole week, so setting money aside this
#                       week lowers still_needed_this_week, not the weekly figure.
#   on_track            saved >= where an even plan from the goal's first week
#                       (starting amount → target by the target week) stands at
#                       the start of this week. Past the date: only if reached.
#   undated purchases (e.g. an emergency fund): progress and milestones only.
#
# Debt payoff: balance, this month's interest, payoff and what-if from
# DebtCalculator; on_track = the balance is at or below where the scheduled
# payments from the goal's first month would have brought it.
#
# Milestones 25/50/75/100%: reached (with the date the set-aside or balance
# update crossed it) or projected (saving: at needed_per_week, the end of the
# week that crosses it, never after target_date; debt: the end of the month
# whose payment crosses it).
class GoalCalculator
  MILESTONES = [25, 50, 75, 100].freeze
  DEFAULT_WHAT_IF = BigDecimal("50")
  SAVING_ASSUMPTIONS = [
    "Weeks run from your week start; the weekly amount is what was left at the start of this week, spread over the weeks left, rounded up.",
    "On track means you've saved at least an even share for every week since the goal began."
  ].freeze
  UNDATED_ASSUMPTIONS = ["No target date, so there's no weekly amount or on-track check."].freeze

  def self.for(goal, now: Time.current, what_if_extra: DEFAULT_WHAT_IF)
    user = goal.user
    new(goal, today: UserClock.today(user, now:), week_start: UserClock.week_start(user, now:),
              started_on: UserClock.date_of(user, goal.created_at || now),
              week_start_of: ->(d) { UserClock.week_start_of(user, d) }, what_if_extra:)
  end

  def initialize(goal, today:, week_start:, started_on:, week_start_of:, what_if_extra: DEFAULT_WHAT_IF)
    @goal = goal
    @today = today
    @week_start = week_start
    @started_on = [started_on, today].min
    @week_start_of = week_start_of
    @what_if_extra = what_if_extra.to_d
  end

  def call = @goal.debt? ? debt : saving

  private

  attr_reader :goal, :today, :week_start, :started_on

  def week_of(date) = @week_start_of.call(date)

  # --- saving goals ---------------------------------------------------------------

  def saving
    target = goal.target_amount
    saved = goal.saved
    this_week = set_asides.select { |c| c.contributed_on >= week_start }.sum(BigDecimal("0"), &:amount)
    result = {
      kind: "saving", saved:, target:, remaining: [target - saved, 0].max.to_d,
      percent: percent(saved, target), set_aside_this_week: this_week,
      weeks_left: nil, needed_per_week: nil, still_needed_this_week: nil, on_track: nil, past_target_date: false
    }
    if goal.target_date
      result.merge!(dated(target, saved, saved - this_week, this_week))
      result[:assumptions] = SAVING_ASSUMPTIONS
    else
      result[:assumptions] = UNDATED_ASSUMPTIONS
    end
    result[:milestones] = saving_milestones(target, saved, result)
    result
  end

  def dated(target, saved, saved_at_week_start, this_week)
    reached = saved >= target
    if goal.target_date < week_start
      return { weeks_left: 0, needed_per_week: [target - saved, 0].max.to_d, still_needed_this_week: [target - saved, 0].max.to_d,
               on_track: reached, past_target_date: true }
    end

    target_week = week_of(goal.target_date)
    weeks_left = ((target_week - week_start).to_i / 7) + 1
    needed = round_up([target - saved_at_week_start, 0].max / weeks_left)
    first_week = week_of(started_on)
    total_weeks = ((target_week - first_week).to_i / 7) + 1
    elapsed = (week_start - first_week).to_i / 7
    expected = (goal.starting_balance + ((target - goal.starting_balance) * elapsed / total_weeks)).round(2)
    { weeks_left:, needed_per_week: needed, still_needed_this_week: [needed - this_week, 0].max.to_d,
      on_track: reached || saved >= expected, past_target_date: false }
  end

  def saving_milestones(target, saved, result)
    crossings = running_totals(goal.starting_balance, set_asides.map { |c| [c.contributed_on, c.amount] })
    MILESTONES.map do |pct|
      threshold = (target * pct / 100).round(2)
      reached_on = crossings.find { |_, total| total >= threshold }&.first
      { percent: pct, amount: threshold, reached: !reached_on.nil?, reached_on:,
        projected_on: reached_on ? nil : saving_projection(threshold, saved, result) }
    end
  end

  # At needed_per_week from now (this week only its unmet share), the end of
  # the week whose set-aside crosses `threshold`; never after target_date.
  def saving_projection(threshold, saved, result)
    needed = result[:needed_per_week]
    return nil if needed.nil? || !needed.positive? || result[:past_target_date]

    total = saved + result[:still_needed_this_week]
    weeks = 1
    while total < threshold
      total += needed
      weeks += 1
    end
    [week_start + ((7 * weeks) - 1), goal.target_date].min
  end

  # [[date, total so far]], starting with the starting amount on the first day.
  def running_totals(start, dated_amounts)
    total = start
    [[started_on, start]] + dated_amounts.sort_by(&:first).map { |date, amount| [date, total += amount] }
  end

  def set_asides = goal.contributions.select(&:set_aside?)

  # --- debt -----------------------------------------------------------------------------

  def debt
    balance = goal.balance
    start = goal.starting_balance
    calc = DebtCalculator.new(balance:, apr: goal.apr, payment: goal.monthly_payment)
    plan = calc.schedule
    what_if = calc.what_if(@what_if_extra)
    {
      kind: "debt", balance:, starting_balance: start, percent_paid: percent(start - balance, start),
      interest_this_month: calc.interest_this_month,
      payoff: payoff_json(plan),
      what_if: { extra: what_if[:extra], **payoff_json(what_if[:schedule]), interest_saved: what_if[:interest_saved],
                 months_sooner: what_if[:months_sooner] },
      on_track: !plan.never_pays_off && balance <= expected_debt_balance,
      milestones: debt_milestones(start, balance, plan),
      assumptions: DebtCalculator::ASSUMPTIONS + ["On track means the balance is at or below where your payments since the goal began would have brought it."]
    }
  end

  def payoff_json(plan)
    { never_pays_off: plan.never_pays_off, months: plan.months,
      payoff_month: plan.months && (today.beginning_of_month >> plan.months).strftime("%Y-%m"),
      total_interest: plan.total_interest }
  end

  # The starting balance after one scheduled payment per month since the goal's first month.
  def expected_debt_balance
    months = month_index(today) - month_index(started_on)
    return goal.starting_balance if months <= 0

    DebtCalculator.new(balance: goal.starting_balance, apr: goal.apr, payment: goal.monthly_payment)
                  .schedule.balance_after(months) || BigDecimal("0")
  end

  def debt_milestones(start, balance, plan)
    updates = goal.contributions.select(&:balance_update?).sort_by { |c| [c.contributed_on, c.id] }
    MILESTONES.map do |pct|
      threshold = (start * (100 - pct) / 100).round(2) # balance at or below this = pct paid
      reached = balance <= threshold
      reached_on = reached ? updates.find { |c| c.balance_after <= threshold }&.contributed_on : nil
      month = reached ? nil : plan.balances.index { |b| b <= threshold }&.+(1)
      { percent: pct, amount: (start - threshold), reached:, reached_on:,
        projected_on: month && (today.beginning_of_month >> month).end_of_month }
    end
  end

  # --- helpers -------------------------------------------------------------------------------

  def percent(part, whole) = whole.positive? ? [[(part * 100 / whole).floor, 0].max, 100].min : 0

  def round_up(value) = value.round(2, BigDecimal::ROUND_CEILING)

  def month_index(date) = (date.year * 12) + date.month
end
