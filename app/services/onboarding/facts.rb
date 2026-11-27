module Onboarding
  # ON1 (onboarding interview), SPEC_ONBOARDING_PLAN §4.1: the facts Rails
  # works out from the user's own imported data to prefill the questions.
  # Deterministic; the user confirms or changes everything. Read-only;
  # dates from UserClock; the same counted rows as SpendingAnalytics.
  #
  #   pay_pattern   Income rows ≥ $200 in the last 90 days on spending/bills
  #                 accounts: weekly (gaps 6–8 days), every 2 weeks (all gaps
  #                 13–15), twice a month (two day-of-month groups, each
  #                 within 3 days, split at the largest gap),
  #                 monthly (gaps 28–31), else irregular; with the last pay
  #                 date, the typical amount (median) and the next pay date.
  #   side_income   monthly median of money in over the last 3 full months on
  #                 side-income accounts (Transfers left out); only if ≥ $50
  #   likely_bills  fixed-category money out from one merchant in ≥ 2 of the
  #                 last 3 full months, every amount within ±10% of their
  #                 median and every day within ±3 of the median day
  #   usual         per flexible category, AN1's median over up to 6 full months
  class Facts
    PAY_MIN = BigDecimal("200")
    PAY_WINDOW_DAYS = 90
    SIDE_INCOME_MIN = BigDecimal("50")
    BILL_AMOUNT_TOLERANCE = BigDecimal("0.10")
    BILL_DAY_TOLERANCE = 3

    def self.call(user, now: Time.current) = new(user, now:).call

    def initialize(user, now:)
      @user = user
      @today = UserClock.today(user, now:)
    end

    def call
      averages = SpendingAnalytics.category_averages(@user, months: 6)
      { pay_pattern:, side_income:, likely_bills:,
        usual_spending: averages[:categories].map { |c| c.slice(:category, :name, :median) },
        months_of_data: averages[:months_covered].size }
    end

    # --- pay pattern ------------------------------------------------------------------

    def pay_pattern
      deposits = SpendingAnalytics.rows(@user, from: @today - PAY_WINDOW_DAYS, to: @today)
                                  .joins(:category).where(categories: { kind: "income" })
                                  .where(accounts: { purpose: %w[spending bills] })
                                  .where("transactions.amount >= ?", PAY_MIN)
                                  .order(:posted_on).pluck(:posted_on, :amount)
      dates = deposits.map(&:first)
      frequency = self.class.frequency(dates)
      last = dates.last
      { frequency:, last_pay_on: last, typical_amount: SpendingAnalytics.median(deposits.map(&:last)),
        next_pay_on: last && self.class.next_pay_on(frequency, dates, @today) }
    end

    def self.frequency(dates)
      return "irregular" if dates.size < 2

      gaps = dates.each_cons(2).map { |a, b| (b - a).to_i }
      mode = gaps.tally.max_by { |gap, count| [count, -gap] }.first
      return "weekly" if mode.between?(6, 8)
      return "biweekly" if gaps.all? { |g| g.between?(13, 15) }
      return "semimonthly" if semimonthly?(dates, gaps)
      return "monthly" if mode.between?(28, 31)

      "irregular"
    end

    # Two clusters of days (early and late in the month), each within 3 days,
    # and gaps of about half a month.
    def self.semimonthly?(dates, gaps)
      early, late = day_clusters(dates)
      return false if early.empty? || late.empty?

      early.max - early.min <= 3 && late.max - late.min <= 3 && gaps.all? { |g| g.between?(10, 20) }
    end

    # Days of the month split into two groups at the largest gap between them
    # (1st/15th, 15th/last day…), so a payday on the 15th isn't mixed with the 1st.
    def self.day_clusters(dates)
      days = dates.map(&:day).sort
      return [days, []] if days.uniq.size < 2

      cut = days.each_cons(2).each_with_index.max_by { |(a, b), _| b - a }.last + 1
      [days.first(cut), days.drop(cut)]
    end

    # The next expected payday on or after today, from the last one.
    def self.next_pay_on(frequency, dates, today)
      last = dates.last
      step = { "weekly" => 7, "biweekly" => 14 }[frequency]
      if step
        nxt = last + step
        nxt += step while nxt < today
        return nxt
      end
      case frequency
      when "monthly"
        nxt = last >> 1
        nxt >>= 1 while nxt < today
        nxt
      when "semimonthly"
        early, late = day_clusters(dates)
        days = [SpendingAnalytics.median(early.map { |d| BigDecimal(d) }).to_i, SpendingAnalytics.median(late.map { |d| BigDecimal(d) }).to_i]
        candidates = (0..2).flat_map do |m|
          month = (today.beginning_of_month >> m)
          days.map { |d| Date.new(month.year, month.month, [d, month.end_of_month.day].min) }
        end
        candidates.select { |d| d >= today }.min
      end
    end

    # --- side income ----------------------------------------------------------------------

    def side_income
      accounts = @user.accounts.active.where(purpose: "side_income").order(:id).to_a
      return nil if accounts.empty?

      months = (1..3).map { |i| @today.beginning_of_month << i }
      totals = months.map do |m|
        Transaction.where(account_id: accounts.map(&:id), posted_on: m..m.end_of_month)
                   .where("transactions.amount > 0")
                   .left_outer_joins(:category).where("categories.id IS NULL OR categories.kind <> 'transfer'")
                   .sum(:amount)
      end
      monthly = SpendingAnalytics.median(totals)
      return nil if monthly.nil? || monthly < SIDE_INCOME_MIN

      { monthly:, account_name: accounts.first.name }
    end

    # --- likely bills ---------------------------------------------------------------------

    def likely_bills
      first = @today.beginning_of_month << 3
      last = @today.beginning_of_month - 1
      rows = SpendingAnalytics.rows(@user, from: first, to: last)
                              .where(category_id: Category.fixed.select(:id))
                              .where("transactions.amount < 0")
                              .includes(:category).order(:posted_on).to_a
      rows.group_by { |t| Categorization::MerchantKey.for(t.normalized_description) }.filter_map do |key, group|
        next nil if group.map { |t| t.posted_on.beginning_of_month }.uniq.size < 2

        amounts = group.map { |t| -t.amount }
        typical = SpendingAnalytics.median(amounts)
        next nil unless amounts.all? { |a| (a - typical).abs <= typical * BILL_AMOUNT_TOLERANCE }

        day = SpendingAnalytics.median(group.map { |t| BigDecimal(t.posted_on.day) }).round.to_i
        next nil unless group.all? { |t| (t.posted_on.day - day).abs <= BILL_DAY_TOLERANCE }

        latest = group.last
        { key:, name: latest.description, amount: typical, day:, category: latest.category.slug, category_name: latest.category.name }
      end.sort_by { |b| [-b[:amount], b[:name]] }
    end
  end
end
