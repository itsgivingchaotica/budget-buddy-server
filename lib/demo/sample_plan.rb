module Demo
  # A stand-in plan for checking Home (C3) and the Plan tab (C8) on the
  # phone before onboarding and plan drafting exist (PL1/PL2). Development
  # only; deterministic; safe to run twice (it adds only what's missing).
  #
  # - Budgets for this month: each flexible category with spending gets its
  #   usual (median of the full months the data covers, AN1) rounded up to
  #   $5; a usual of $0 gets no budget.
  # - Bills: Rent due in 2 days; Phone due on the first day of this week,
  #   unpaid (so Home shows "Was due …" unless today is that day).
  # - Goal: Car insurance, $600 in 8 weeks.
  module SamplePlan
    class Refused < StandardError; end

    module_function

    def call(user:, env: Rails.env, now: Time.current)
      raise Refused, "demo:sample_plan runs only in development or test (this is #{env})" unless %w[development test].include?(env.to_s)

      today = UserClock.today(user, now:)
      counts = { budgets: 0, bills: 0, goals: 0 }
      month = UserClock.month_start(user, now:)
      if user.category_budgets.where(effective_from: month).none?
        SpendingAnalytics.category_averages(user, months: 6)[:categories].each do |line|
          next unless line[:median].positive? # usually no spending: no budget (SPEC_ONBOARDING_PLAN §6.1)

          amount = (line[:median] / 5).ceil * 5
          user.category_budgets.create!(category: Category.find_by!(slug: line[:category]), amount:, effective_from: month)
          counts[:budgets] += 1
        end
      end
      bill = lambda do |name, slug, amount, due|
        next if user.obligations.exists?(name:) || (category = Category.fixed.find_by(slug:)).nil?

        user.obligations.create!(name:, amount:, category:, first_due_on: due, recurrence: "monthly")
        counts[:bills] += 1
      end
      bill.("Rent", "rent", "1200", today + 2)
      bill.("Phone", "utilities", "45", UserClock.week_start(user, now:))
      unless user.goals.exists?(name: "Car insurance")
        user.goals.create!(goal_type: "upcoming_payment", name: "Car insurance", target_amount: "600", target_date: today + 56)
        counts[:goals] += 1
      end
      counts
    end
  end
end
