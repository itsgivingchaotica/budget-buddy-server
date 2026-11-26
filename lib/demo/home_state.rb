module Demo
  # C3 screenshots: puts one user into a chosen Home state, using the real
  # services: budgets (DM-3), bills and payments (OB1), a goal (G1), and this
  # week's transactions through the real CSV importer (I2), with descriptions
  # the keyword rules know, so no Claude call is made.
  #
  #   no_plan  no budgets, bills or goals (imported history stays)
  #   normal   budgets so this week is comfortably under; Rent due in 3 days,
  #            Phone due on the week's first day and already paid, Streaming
  #            due in 5 days; Car insurance $600 in 8 weeks
  #   over     the same, with budgets low enough to be about $20 over this week
  #
  # Every run first removes what an earlier run made (the user's budgets,
  # bills and goals, and the week rows it imported), so a state replaces the
  # previous one. Guards as demo:reset: development only; the demo user by
  # default, another account only when named explicitly by email.
  module HomeState
    STATES = %w[no_plan normal over].freeze
    FILENAME = "home-state-this-week.csv".freeze
    OVER_BY = BigDecimal("20")
    # This week's purchases on the main account (all match keyword rules).
    PURCHASES = [["WHOLE FOODS MARKET", "-48.20"], ["STARBUCKS", "-6.40"], ["CHIPOTLE", "-14.75"], ["SHELL OIL", "-38.00"]].freeze
    # Budget shares for the four categories above + entertainment.
    SHARES = { "groceries" => 0.45, "dining-out" => 0.2, "transportation" => 0.2, "entertainment" => 0.15 }.freeze
    NORMAL_MONTHLY = BigDecimal("1200")

    class Refused < StandardError; end

    module_function

    def call(state:, email: Reset::DEMO_EMAIL, env: Rails.env, now: Time.current)
      raise Refused, "demo:home_state runs only in development (this is #{env})" unless env.to_s == "development"
      raise Refused, "unknown state #{state.inspect}; use one of #{STATES.join(', ')}" unless STATES.include?(state.to_s)

      user = User.find_by_email_ci(email)
      raise Refused, "no user with that email (run demo:seed, or sign in once in the app)" if user.nil?

      today = UserClock.today(user, now:)
      week_start = UserClock.week_start(user, now:)
      ActiveRecord::Base.transaction { clear!(user) }
      return { state: state.to_s, user_id: user.id } if state.to_s == "no_plan"

      spent = import_week!(user, today, week_start)
      monthly = state.to_s == "over" ? over_monthly(user, spent, week_start) : NORMAL_MONTHLY
      ActiveRecord::Base.transaction do
        budgets!(user, monthly, week_start)
        bills!(user, today, week_start)
        user.goals.create!(goal_type: "upcoming_payment", name: "Car insurance", target_amount: "600", target_date: today + 56)
      end
      { state: state.to_s, user_id: user.id, spent_this_week: spent.to_s("F"), monthly_budget: monthly.to_s("F") }
    end

    # Plan data and this task's own imported rows; real imports stay.
    def clear!(user)
      GoalContribution.where(goal_id: user.goals.select(:id)).delete_all
      Goal.where(user:).delete_all
      ObligationPayment.where(obligation_id: user.obligations.select(:id)).delete_all
      Obligation.where(user:).delete_all
      CategoryBudget.where(user:).delete_all
      imports = Import.where(account_id: user.accounts.select(:id), filename: FILENAME)
      rows = Transaction.where(import_id: imports.select(:id))
      TransferLink.where(outflow_transaction_id: rows.select(:id)).or(TransferLink.where(inflow_transaction_id: rows.select(:id))).delete_all
      CategoryCorrection.where(transaction_id: rows.select(:id)).delete_all
      rows.delete_all
      imports.delete_all
    end

    # Purchases spread over this week up to today on the main account, and a
    # tiny interest row dated today on every other active account, so
    # data_through is today and Home isn't "stale". Returns the money out.
    def import_week!(user, today, week_start)
      accounts = user.accounts.active.order(:id).to_a
      main = accounts.find { |a| a.purpose == "spending" } || accounts.first
      main ||= user.accounts.create!(name: "Everyday Checking", kind: "checking", purpose: "spending")
      days = (week_start..today).to_a
      rows = PURCHASES.each_with_index.map { |(desc, amount), i| [days[(i * days.size) / PURCHASES.size], desc, amount] }
      rows << [today, "INTEREST PAID", "0.01"] unless rows.any? { |d, _, _| d == today }
      import_csv!(main, rows)
      (accounts - [main]).each { |a| import_csv!(a, [[today, "INTEREST PAID", "0.01"]]) }
      PURCHASES.sum(BigDecimal("0")) { |_, amount| -BigDecimal(amount) }
    end

    def import_csv!(account, rows)
      csv = "date,description,amount\n" + rows.map { |d, desc, amount| "#{d.iso8601},#{desc},#{amount}" }.join("\n") + "\n"
      CsvImport::Importer.call(account:, file: Seeder::Upload.new(csv, FILENAME))
    end

    # A monthly total whose share for this week is (spent - $20).
    def over_monthly(_user, spent, week_start)
      per_month = (week_start..(week_start + 6)).sum(BigDecimal("0")) { |d| BigDecimal("1") / d.end_of_month.day }
      ((spent - OVER_BY) / per_month).round.to_d
    end

    # Budgets in every month this week touches (DM-3 rows start on the 1st).
    def budgets!(user, monthly, week_start)
      [week_start.beginning_of_month, (week_start + 6).beginning_of_month].uniq.each do |month|
        SHARES.each do |slug, share|
          category = Category.flexible.find_by(slug:) or next
          user.category_budgets.create!(category:, amount: (monthly * BigDecimal(share.to_s)).round(2), effective_from: month)
        end
      end
    end

    def bills!(user, today, week_start)
      bill = lambda do |name, slug, amount, due|
        category = Category.fixed.find_by(slug:) or return nil
        user.obligations.create!(name:, amount:, category:, first_due_on: due, recurrence: "monthly")
      end
      bill.("Rent", "rent", "1200", today + 3)
      phone = bill.("Phone", "utilities", "45", week_start)
      phone&.payments&.create!(due_on: week_start, paid_on: today)
      bill.("Streaming", "subscriptions", "15.99", today + 5)
    end
  end
end
