# AN1 (spending analytics): the single source of spending figures for Home,
# the Plan tab, onboarding/plan drafting and the coach (plan AD9). Read-only,
# BigDecimal, the user's dates (UserClock).
#
# Which transactions count, everywhere:
#   - the user's own, on accounts that aren't archived, dated on or before
#     today (never future-dated rows);
#   - Transfers are left out (a row only gets the Transfers category when
#     the user confirms the transfer pair, TR1);
#   - spending per category = money out minus refunds in that category,
#     never below 0;
#   - uncategorized rows (waiting for review) are their own line and count
#     only money out: money in on an uncategorized row could be pay, so it
#     never cancels spending;
#   - income = the Income category, net.
module SpendingAnalytics
  MAX_SUMMARY_DAYS = 731 # 24 months, for the coach (SPEC_COACH_QA §5)
  TOP_LINES = 12
  NEAR_SHARE = BigDecimal("0.9") # "near" once 90% of a budget is spent
  ZERO = BigDecimal("0")

  module_function

  # --- the counted rows ----------------------------------------------------------------

  def rows(user, from:, to:)
    to = [to, UserClock.today(user)].min
    Transaction.joins(:account)
               .where(accounts: { user_id: user.id, archived_at: nil })
               .where(posted_on: from..to)
  end

  # Spending, uncategorized money out, income and row count in a range.
  #   { by_category: { Category => spent }, uncategorized:, income:, count: }
  def totals(user, from:, to:, category: nil, merchant_contains: nil)
    scope = rows(user, from:, to:)
    if merchant_contains.present?
      scope = scope.where("transactions.normalized_description LIKE ?", "%#{Transaction.sanitize_sql_like(merchant_contains.to_s.upcase.strip)}%")
    end
    scope = scope.where(category_id: category.id) if category
    sums = scope.group(:category_id).sum(:amount)
    outflow_uncategorized = scope.where(category_id: nil).where("transactions.amount < 0").sum(:amount)
    categories = Category.where(id: sums.keys.compact).index_by(&:id)
    by_category = {}
    income = ZERO
    sums.each do |category_id, sum|
      c = categories[category_id]
      next if c.nil?

      if c.spending? then by_category[c] = [ZERO - sum, ZERO].max
      elsif c.income? then income += sum
      end
    end
    counted = scope.left_outer_joins(:category).where("categories.id IS NULL OR categories.kind IN ('spending','income')").count
    { by_category:, uncategorized: ZERO - outflow_uncategorized, income:, count: counted }
  end

  # The data the user has: first row, and data_through = the earliest of each
  # active account's latest row (spec §2), so a figure never claims days one
  # account hasn't reached.
  def coverage(user)
    per_account = Transaction.joins(:account).where(accounts: { user_id: user.id, archived_at: nil })
                             .group(:account_id).pluck(Arel.sql("MIN(posted_on)"), Arel.sql("MAX(posted_on)"))
    return { data_from: nil, data_through: nil } if per_account.empty?

    { data_from: per_account.map(&:first).min, data_through: per_account.map(&:last).min }
  end

  # --- summary (coach, AN2) ---------------------------------------------------------------

  # Spending and income in [from, to], with the same-length period just
  # before it and the change.
  def summary(user, from:, to:, category: nil, merchant_contains: nil)
    raise ArgumentError, "to is before from" if to < from
    raise ArgumentError, "range longer than #{MAX_SUMMARY_DAYS} days" if (to - from).to_i >= MAX_SUMMARY_DAYS

    now = totals(user, from:, to:, category:, merchant_contains:)
    length = (to - from).to_i + 1
    prev_to = from - 1
    prev_from = prev_to - (length - 1)
    before = totals(user, from: prev_from, to: prev_to, category:, merchant_contains:)
    spent_now = total_spent(now)
    spent_before = total_spent(before)
    cov = coverage(user)
    {
      from:, to:, total_spent: spent_now, total_income: now[:income],
      categories: lines(now[:by_category]), uncategorized: now[:uncategorized],
      transaction_count: now[:count],
      previous: { from: prev_from, to: prev_to, total_spent: spent_before, total_income: before[:income] },
      change: { amount: spent_now - spent_before, percent: percent_change(spent_before, spent_now) },
      **cov, coverage_note: coverage_note(cov, from, to, UserClock.today(user))
    }
  end

  def total_spent(t) = t[:by_category].values.sum(ZERO) + t[:uncategorized]

  # Largest first; after the top 12, one "Everything else" line.
  def lines(by_category)
    sorted = by_category.select { |_, v| v.positive? }.sort_by { |c, v| [-v, c.position || 0, c.id] }
    top = sorted.first(TOP_LINES).map { |c, v| { category: c.slug, name: c.name, spent: v } }
    rest = sorted.drop(TOP_LINES)
    top << { category: nil, name: "Everything else", spent: rest.sum(ZERO) { |_, v| v } } if rest.any?
    top
  end

  def percent_change(before, now)
    return nil unless before.positive?

    ((now - before) * 100 / before).round(1)
  end

  def coverage_note(cov, from, to, today)
    return "No transactions imported yet." if cov[:data_through].nil?

    notes = []
    notes << "Your data starts on #{cov[:data_from].iso8601}." if from < cov[:data_from]
    notes << "Your data runs through #{cov[:data_through].iso8601}." if [to, today].min > cov[:data_through]
    notes.empty? ? nil : notes.join(" ")
  end

  # --- budget vs actual (Plan → Budgets, coach) ------------------------------------------------

  # The month's budgets (the row in effect on the 1st) against spending in
  # that month so far.
  def budget_vs_actual(user, month:)
    month = month.beginning_of_month
    budgets = CategoryBudget.in_effect_on(user, month).includes(:category).to_a
    t = totals(user, from: month, to: month.end_of_month)
    flexible = Category.flexible.order(:position, :id).to_a
    budgeted_ids = budgets.map(&:category_id)
    rows = flexible.filter_map do |c|
      budget = budgets.find { |b| b.category_id == c.id }
      next nil unless budget

      spent = t[:by_category].fetch(c, ZERO)
      { category: c.slug, name: c.name, budget: budget.amount, spent:, remaining: budget.amount - spent,
        status: status(budget.amount, spent) }
    end
    unbudgeted = flexible.reject { |c| budgeted_ids.include?(c.id) }
                         .filter_map { |c| (s = t[:by_category].fetch(c, ZERO)).positive? ? { category: c.slug, name: c.name, spent: s } : nil }
    total_budget = rows.sum(ZERO) { |r| r[:budget] }
    total_spent = rows.sum(ZERO) { |r| r[:spent] }
    {
      month: month.strftime("%Y-%m"), plan_exists: rows.any?, categories: rows, unbudgeted:,
      uncategorized: t[:uncategorized],
      totals: { budget: total_budget, spent: total_spent, remaining: total_budget - total_spent },
      data_through: coverage(user)[:data_through]
    }
  end

  def status(budget, spent)
    return "over" if spent > budget
    return "near" if budget.positive? && spent >= budget * NEAR_SHARE

    "under"
  end

  # --- usual spending (plan drafting, the change-a-budget sheet) ----------------------------

  # The last up to `months` full months before this one that the data
  # covers (data_from on or before the 1st, data_through on or after the
  # last day); months the data doesn't cover are left out, never counted as $0.
  def covered_months(user, months:, today: UserClock.today(user))
    cov = coverage(user)
    return [] if cov[:data_through].nil?

    (1..months).map { |i| today.beginning_of_month << i }
               .select { |m| cov[:data_from] <= m && cov[:data_through] >= m.end_of_month }
  end

  # Per flexible category with spending: mean and median of monthly spending
  # over the covered full months, the months used, and the uncategorized
  # money out in those months (excluded, reported as a note).
  def category_averages(user, months:)
    covered = covered_months(user, months:)
    monthly = covered.map { |m| totals(user, from: m, to: m.end_of_month) }
    result = Category.flexible.order(:position, :id).filter_map do |c|
      values = monthly.map { |t| t[:by_category].fetch(c, ZERO) }
      next nil if values.none?(&:positive?)

      { category: c.slug, name: c.name, mean: mean(values), median: median(values), months: covered.size }
    end
    { months_covered: covered.map { |m| m.strftime("%Y-%m") }, categories: result,
      uncategorized_excluded: monthly.sum(ZERO) { |t| t[:uncategorized] } }
  end

  # The change-a-budget sheet (SCREENS_PLAN §3.1): one flexible category's
  # spending this month, its mean over the last up to 3 covered full months,
  # and the weekly equivalent of `amount` (× 12 / 52, whole dollars, down).
  def category_context(user, category, amount:)
    month = UserClock.month_start(user)
    covered = covered_months(user, months: 3)
    values = covered.map { |m| totals(user, from: m, to: m.end_of_month, category:)[:by_category].fetch(category, ZERO) }
    {
      category: category.slug, name: category.name, month: month.strftime("%Y-%m"), amount:,
      weekly_equivalent: amount && (amount * 12 / 52).floor.to_d,
      average_last_3_months: mean(values), months_averaged: covered.size,
      spent_this_month: totals(user, from: month, to: month.end_of_month, category:)[:by_category].fetch(category, ZERO)
    }
  end

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2).round(2)
  end

  def mean(values) = values.empty? ? nil : (values.sum(ZERO) / values.size).round(2)
end
