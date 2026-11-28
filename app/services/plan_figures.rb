# PL1 (plan drafting), SPEC_ONBOARDING_PLAN §6.2 as amended by D-032 (plan
# drafting and approval details): the income check and every figure on a
# draft plan. Deterministic, and the same code runs when the draft is built
# and after each adjustment (PATCH), so the fit line always matches.
#
#   income     regular pay: the median of the last 3 full months of Income on
#              spending/bills accounts, unless the user changed the paycheck
#              amount in question 1 (then amount × paychecks per month, with
#              OB1's monthly-average factors; twice a month = 2);
#              pay "It varies": the stated floor (ON2 follow-up) if answered,
#              else the LOWEST of the last 3 full months;
#              plus ON1's side income when the user chose "Yes, count it"
#   committed  kept bills (OB1 Bills.monthly_total) + dated saving goals'
#              weekly need (G2) × 52 / 12 + each debt goal's monthly payment,
#              unless a kept bill is in Debt Payments (never counted twice)
#   room       income − committed;  fits = everyday budgets ≤ room;
#              unplanned = room − everyday budgets when positive (D-034)
#
# Money is stored in the payload as two-decimal strings (as the API sends it).
module PlanFigures
  PER_PAYCHECK = Bills::PER_MONTH.slice("weekly", "biweekly", "monthly").merge("semimonthly" => 2).freeze
  WEEKS_PER_MONTH = Rational(52, 12)
  INCOME_LABELS = {
    "median" => "Based on your usual monthly income",
    "your_paycheck" => "Based on the paycheck you told us",
    "floor" => "Based on the month you can count on",
    "lowest_month" => "Based on your lowest recent month",
    "none" => "No income found yet"
  }.freeze

  module_function

  # --- income (§6.2) ------------------------------------------------------------

  def income(user, answers, today:, now: Time.current)
    pay = answers["pay"].is_a?(Hash) ? answers["pay"] : {}
    monthly = monthly_income(user, today:)
    base, basis =
      if pay["frequency"] == "irregular"
        floor = money(answers.dig("follow_ups", "irregular_income_floor"))
        floor ? [floor, "floor"] : [monthly.min, "lowest_month"]
      else
        paycheck = money(pay["typical_amount"])
        detected = Onboarding::Facts.new(user, now:).pay_pattern[:typical_amount]&.round(2)
        if paycheck && paycheck != detected && PER_PAYCHECK.key?(pay["frequency"])
          [(paycheck * PER_PAYCHECK.fetch(pay["frequency"])).round(2), "your_paycheck"]
        else
          [SpendingAnalytics.median(monthly), "median"]
        end
      end
    basis = "none" if base.nil?
    side = answers["side_income"] == "yes" ? Onboarding::Facts.new(user, now:).side_income&.dig(:monthly) : nil
    total = base || side ? (base || 0) + (side || 0) : nil
    { monthly: total&.to_d&.round(2), pay: base&.to_d&.round(2), side_income: side&.round(2), basis:, label: INCOME_LABELS.fetch(basis) }
  end

  # Income money in, per full month the data covers (last 3).
  def monthly_income(user, today:)
    SpendingAnalytics.covered_months(user, months: 3, today:).map do |m|
      SpendingAnalytics.rows(user, from: m, to: m.end_of_month)
                       .joins(:category).where(categories: { kind: "income" })
                       .where(accounts: { purpose: %w[spending bills] })
                       .sum(:amount).to_d
    end
  end

  # --- bills and goals as the draft holds them (answer-shaped, with keys) -----------

  # The kept bills from question 3, plus a Rent bill from the user's own
  # spending when they answered the ON2 follow-up `bill_missing` with "Add it".
  def draft_bills(user, answers, today:)
    bills = Array(answers["bills"]).each_with_index.map do |b, i|
      { "key" => "bill_#{i}", "name" => b["name"], "amount" => b["amount"], "day" => b["day"], "category" => b["category"],
        "included" => true, "from_spending" => false }
    end
    if answers.dig("follow_ups", "bill_missing") == "add_it" && (rent = rent_from_spending(user, today:))
      bills << rent.merge("key" => "bill_#{bills.size}", "included" => true, "from_spending" => true)
    end
    bills
  end

  # Median monthly Rent spending over the last 3 full months, on the usual day.
  def rent_from_spending(user, today:)
    category = Category.fixed.find_by(slug: "rent") or return nil
    months = SpendingAnalytics.covered_months(user, months: 3, today:)
    spent = months.map { |m| SpendingAnalytics.totals(user, from: m, to: m.end_of_month, category:)[:by_category].fetch(category, 0).to_d }
    amount = SpendingAnalytics.median(spent)
    return nil unless amount&.positive?

    days = months.empty? ? [] : SpendingAnalytics.rows(user, from: months.min, to: months.max.end_of_month)
                                                  .where(category_id: category.id).where("transactions.amount < 0")
                                                  .pluck(:posted_on).map { |d| BigDecimal(d.day) }
    { "name" => "Rent", "amount" => format("%.2f", amount), "day" => (SpendingAnalytics.median(days) || 1).round.to_i, "category" => "rent" }
  end

  def draft_goals(answers)
    Array(answers["goals"]).each_with_index.map { |g, i| g.merge("key" => "goal_#{i}", "included" => true) }
  end

  # --- every figure, from the draft's inputs ------------------------------------------

  # Fills in each bill's monthly amount, each goal's G2 figures and monthly
  # commitment, and the committed / room / everyday total / fit line.
  def compute(user, payload, now: Time.current)
    today = UserClock.today(user, now:)
    bills = payload["bills"].map do |b|
      monthly = b["included"] ? Bills.monthly_total([Obligation.new(amount: BigDecimal(b["amount"]), recurrence: "monthly", interval: 1)], today:) : BigDecimal("0")
      b.merge("monthly" => money_s(monthly))
    end
    debt_bill = bills.any? { |b| b["included"] && b["category"] == "debt-payments" }
    goals = payload["goals"].map do |g|
      goal = goal_record(user, g)
      figures = GoalCalculator.for(goal, now:).call
      commitment =
        if !g["included"] then BigDecimal("0")
        elsif goal.debt? then debt_bill ? BigDecimal("0") : goal.monthly_payment
        elsif goal.target_date && figures[:needed_per_week] then (figures[:needed_per_week] * WEEKS_PER_MONTH).round(2)
        else BigDecimal("0")
        end
      g.merge("figures" => jsonable(figures), "monthly_commitment" => money_s(commitment))
    end

    committed_bills = bills.sum(BigDecimal("0")) { |b| BigDecimal(b["monthly"]) }
    committed_goals = goals.reject { |g| g["kind"] == "debt_payoff" }.sum(BigDecimal("0")) { |g| BigDecimal(g["monthly_commitment"]) }
    committed_debt = goals.select { |g| g["kind"] == "debt_payoff" }.sum(BigDecimal("0")) { |g| BigDecimal(g["monthly_commitment"]) }
    committed = committed_bills + committed_goals + committed_debt
    everyday = payload["categories"].sum(BigDecimal("0")) { |c| BigDecimal(c["amount"]) }
    income = payload.dig("income", "monthly") && BigDecimal(payload["income"]["monthly"])
    room = income && income - committed
    payload.merge(
      "bills" => bills, "goals" => goals,
      "committed" => { "bills" => money_s(committed_bills), "goals" => money_s(committed_goals), "debt" => money_s(committed_debt), "total" => money_s(committed) },
      "room" => room && money_s(room), "everyday_total" => money_s(everyday),
      "fits" => room && everyday <= room, "gap" => room && money_s([everyday - room, 0].max),
      "unplanned" => room && money_s([room - everyday, 0].max) # D-034: "Unplanned each month" on C6
    )
  end

  # An unsaved Goal from a draft goal, for G2's figures.
  def goal_record(user, g)
    user.goals.new(Onboarding::Interview.goal_attributes(g["kind"], g).merge(source: "interview"))
  end

  # BigDecimal → "0.00" strings and dates → ISO strings, all the way down.
  def jsonable(value)
    case value
    when BigDecimal then money_s(value)
    when Hash then value.to_h { |k, v| [k.to_s, jsonable(v)] }
    when Array then value.map { |v| jsonable(v) }
    when Date then value.iso8601
    else value
    end
  end

  def money_s(value)
    rounded = value.to_d.round(2)
    rounded = BigDecimal("0") if rounded.zero?
    format("%.2f", rounded)
  end

  def money(value)
    return nil if value.nil? || value.to_s.strip.empty?

    BigDecimal(value.to_s)
  rescue ArgumentError
    nil
  end
end
