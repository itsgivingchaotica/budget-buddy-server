# W1 (Home outlook): exactly docs/product/SPEC_LEFT_TO_SPEND.md. Read-only,
# BigDecimal, the user's own dates (UserClock). Spending comes from the
# shared analytics (SpendingAnalytics.totals), so Home, Plan and the coach
# count the same rows (D-028: uncategorized money in isn't counted; each
# flexible category floors at $0).
#
#   left = allowance - spent, where
#   allowance = for each day of the user's week, each flexible category's
#               monthly budget (in effect on that month's 1st) ÷ days in that month
#   spent     = flexible spending + uncategorized money out, from the week's
#               start to min(today, data_through)
#
# Bills (§8.1): due today … today + 6, plus earlier this week: unpaid ones
# as overdue, paid ones as paid (so Mark paid can be undone on Home). Goal contributions (§8.2): active dated saving goals still short
# of their target. Neither is subtracted from `left`.
class WeeklyOutlook
  STALE_AFTER_DAYS = 7
  ZERO = BigDecimal("0")

  def self.call(user, now: Time.current) = new(user, now:).call

  def initialize(user, now:)
    @user = user
    @now = now
    @today = UserClock.today(user, now:)
    @week_start = UserClock.week_start(user, now:)
    @week_end = @week_start + 6
  end

  def call
    data_through = SpendingAnalytics.coverage(@user)[:data_through]
    allowances = allowance_by_category
    spending = spending(data_through)
    {
      state: state(allowances, data_through),
      today: @today, week: { start: @week_start, end: @week_end }, data_through:,
      left_to_spend: left_to_spend(allowances, spending),
      bills_due: bills_due,
      goal_contributions: goal_contributions,
      assumptions: assumptions(data_through, spending[:uncategorized_count])
    }
  end

  private

  # --- left to spend ---------------------------------------------------------------

  # { Category => allowance } for flexible categories with a budget on any day
  # this week. Each month's share = budget × (this week's days in that month)
  # ÷ (days in that month), so a week across a month boundary takes each
  # day from the right month (§3.1).
  def allowance_by_category
    flexible = Category.flexible.index_by(&:id)
    (@week_start..@week_end).group_by(&:beginning_of_month).each_with_object({}) do |(month, days), acc|
      CategoryBudget.in_effect_on(@user, month).each do |budget|
        category = flexible[budget.category_id] or next
        acc[category] = acc.fetch(category, ZERO) + (budget.amount * days.size / month.end_of_month.day)
      end
    end
  end

  def spending(data_through)
    window_end = data_through && [@today, data_through].min
    if window_end.nil? || window_end < @week_start
      return { by_category: {}, uncategorized: ZERO, uncategorized_count: 0 }
    end

    t = SpendingAnalytics.totals(@user, from: @week_start, to: window_end)
    flexible = Category.flexible.to_a
    { by_category: t[:by_category].select { |c, _| flexible.include?(c) },
      uncategorized: t[:uncategorized],
      uncategorized_count: SpendingAnalytics.rows(@user, from: @week_start, to: window_end).where(category_id: nil).count }
  end

  def left_to_spend(allowances, spending)
    allowance = allowances.values.sum(ZERO)
    spent = spending[:by_category].values.sum(ZERO) + spending[:uncategorized]
    categories = (allowances.keys | spending[:by_category].keys).sort_by { |c| [c.position || 0, c.id] }
    by_category = categories.map do |c|
      a = allowances.fetch(c, ZERO)
      s = spending[:by_category].fetch(c, ZERO)
      { category: c.slug, name: c.name, allowance: a, spent: s, left: a - s }
    end
    { allowance:, spent:, left: allowance - spent, uncategorized_spent: spending[:uncategorized],
      uncategorized_count: spending[:uncategorized_count], by_category: }
  end

  # §4.1, in this order.
  def state(allowances, data_through)
    return "no_plan" if allowances.empty?
    return "stale" if data_through.nil? || (@today - data_through).to_i > STALE_AFTER_DAYS
    return "no_data_this_week" if data_through < @week_start

    "ok"
  end

  # --- bills and goals ---------------------------------------------------------------

  def bills_due
    window_end = @today + (Bills::WINDOW_DAYS - 1)
    from = [@week_start, @today].min
    # Earlier this week stays listed once paid (as paid, not overdue), so the
    # tick shows and the user can undo it (phone test, 2026-11-26).
    items = Bills.occurrences(@user.obligations.active.includes(:category), from:, to: window_end).map do |o|
      overdue = o.due_on < @today && !o.paid?
      { obligation_id: o.obligation.id, name: o.obligation.name, amount: o.obligation.amount, due_on: o.due_on,
        paid: o.paid?, paid_on: o.paid_on, overdue: }
    end
    { window: { start: @today, end: window_end }, items: }
  end

  def goal_contributions
    @user.goals.active.where(goal_type: Goal::SAVING_TYPES).where.not(target_date: nil).includes(:contributions)
         .order(:target_date, :id).filter_map do |goal|
      r = GoalCalculator.for(goal, now: @now).call
      next nil unless r[:remaining].positive?

      { goal_id: goal.id, name: goal.name, needed_this_week: r[:needed_per_week], set_aside_this_week: r[:set_aside_this_week],
        still_needed_this_week: r[:still_needed_this_week], target_date: goal.target_date }
    end
  end

  def assumptions(data_through, uncategorized_count)
    list = ["Only everyday (flexible) categories count; bills are listed separately.",
            "Weekly share = your monthly budget spread evenly across the days of the month."]
    list << (data_through ? "Based on transactions imported through #{data_through.iso8601}." : "No transactions imported yet.")
    if uncategorized_count.positive?
      list << "Includes #{uncategorized_count} uncategorized transaction#{'s' unless uncategorized_count == 1}; " \
              "money coming in isn't counted until it's categorized."
    end
    list
  end
end
