module Onboarding
  # ON1 (onboarding interview), SPEC_ONBOARDING_PLAN §4.2: the five
  # questions, prefilled from Facts, and the user's answers, saved after
  # every answer so onboarding resumes where it stopped. Question text is
  # templated by Rails from facts (never model text). Answers live in
  # financial_profiles.answers (version 1); the pay pattern and the change
  # appetite are also written to the profile's typed columns.
  module Interview
    VERSION = 1
    STEPS = %w[accounts interview merchants plan done].freeze
    SIDE_INCOME = %w[yes sometimes no].freeze
    GOAL_KINDS = %w[upcoming_payment purchase emergency_fund debt_payoff].freeze
    MAX_BILLS = 20
    MAX_GOALS = 5
    FREQUENCY_LABELS = { "weekly" => "Weekly", "biweekly" => "Every 2 weeks", "semimonthly" => "Twice a month",
                         "monthly" => "Monthly", "irregular" => "It varies" }.freeze
    APPETITE_LABELS = { "keep" => "Keep things as they are", "trim" => "Small trims", "push" => "Push me a bit" }.freeze

    class Invalid < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super("invalid answers")
      end
    end

    module_function

    def profile(user) = user.financial_profile || user.create_financial_profile!

    # GET /onboarding: the step, the facts, the questions and saved answers.
    def state(user, now: Time.current)
      facts = Facts.call(user, now:)
      p = profile(user)
      answers = p.answers.is_a?(Hash) ? p.answers : {}
      { version: VERSION, step: answers["step"] || "accounts",
        has_import: user.imports.where(status: "completed").where("inserted_count > 0").exists?,
        facts:, questions: questions(facts, answers),
        follow_ups: FollowUps.new(user, client: nil, now:).stored,
        answers: answers.except("step", "follow_ups_asked") }
    end

    # PUT /onboarding/answers: partial, validated per question; nothing is
    # saved if any part is invalid.
    def save!(user, params)
      p = profile(user)
      answers = (p.answers.is_a?(Hash) ? p.answers : {}).dup
      errors = {}
      updates = {}
      params = params.to_h.stringify_keys

      if params.key?("step")
        STEPS.include?(params["step"]) ? answers["step"] = params["step"] : errors["step"] = ["is not a known step"]
      end
      if params.key?("pay")
        pay, problems = pay(params["pay"])
        if problems.empty?
          answers["pay"] = pay
          updates.merge!(pay_frequency: pay["frequency"], next_pay_on: pay["next_pay_on"], typical_pay_amount: pay["typical_amount"])
        else
          errors["pay"] = problems
        end
      end
      if params.key?("side_income")
        SIDE_INCOME.include?(params["side_income"]) ? answers["side_income"] = params["side_income"] : errors["side_income"] = ["must be yes, sometimes or no"]
      end
      if params.key?("bills")
        bills, problems = bills(params["bills"])
        problems.empty? ? answers["bills"] = bills : errors["bills"] = problems
      end
      if params.key?("goals")
        goals, problems = goals(user, params["goals"])
        problems.empty? ? answers["goals"] = goals : errors["goals"] = problems
      end
      if params.key?("change_appetite")
        if FinancialProfile::CHANGE_APPETITES.include?(params["change_appetite"])
          answers["change_appetite"] = params["change_appetite"]
          updates[:change_appetite] = params["change_appetite"]
        else
          errors["change_appetite"] = ["must be keep, trim or push"]
        end
      end
      if params.key?("follow_ups")
        follow, problems = follow_up_answers(user, answers, params["follow_ups"])
        if problems.empty?
          answers["follow_ups"] = (answers["follow_ups"] || {}).merge(follow)
        else
          errors["follow_ups"] = problems
        end
      end
      raise Invalid, errors if errors.any?

      p.update!(updates.merge(answers:, answers_version: VERSION))
      p
    end

    # --- questions (spec §4.2) ------------------------------------------------------------

    def questions(facts, answers)
      pay = facts[:pay_pattern]
      list = []
      hint = if pay[:last_pay_on] && pay[:frequency] != "irregular"
               "Looks like #{FREQUENCY_LABELS[pay[:frequency]].downcase}, last on #{pay[:last_pay_on].strftime('%a, %b %-d')}."
             end
      list << { id: "pay", text: "How often does your main paycheck arrive?", hint:,
                options: FREQUENCY_LABELS.map { |value, label| { value:, label: } },
                prefill: answers["pay"] || { "frequency" => pay[:frequency], "next_pay_on" => pay[:next_pay_on]&.iso8601,
                                             "typical_amount" => pay[:typical_amount] && format("%.2f", pay[:typical_amount]) } }
      if (side = facts[:side_income])
        list << { id: "side_income",
                  text: "I see about $#{side[:monthly].floor} a month coming into #{side[:account_name]}. Is that income from your side job?",
                  options: [{ value: "yes", label: "Yes, count it" }, { value: "sometimes", label: "Sometimes, don't count on it" },
                            { value: "no", label: "No, it's not income" }],
                  prefill: answers["side_income"] }
      end
      list << { id: "bills", text: "These look like regular bills. Keep the ones that are right.",
                prefill: answers["bills"] || facts[:likely_bills].map { |b| bill_json(b) } }
      list << { id: "goals", text: "What are you saving for or paying down?",
                options: [{ value: "upcoming_payment", label: "Upcoming payment" }, { value: "purchase", label: "Something to buy" },
                          { value: "emergency_fund", label: "Emergency fund" }, { value: "debt_payoff", label: "Pay off a debt" }],
                prefill: answers["goals"] || [] }
      list << { id: "change_appetite", text: "How big a change feels right?",
                options: APPETITE_LABELS.map { |value, label| { value:, label: } },
                prefill: answers["change_appetite"] || "trim" }
      list
    end

    def bill_json(b)
      { "name" => b[:name], "amount" => format("%.2f", b[:amount]), "day" => b[:day], "category" => b[:category], "detected" => true }
    end

    # --- answer validation -----------------------------------------------------------------

    def pay(value)
      v = hash(value)
      return [nil, ["must be an object"]] if v.nil?

      problems = []
      problems << "frequency must be one of #{FinancialProfile::PAY_FREQUENCIES.join(', ')}" unless FinancialProfile::PAY_FREQUENCIES.include?(v["frequency"])
      next_pay = date(v["next_pay_on"]) if v["next_pay_on"].present?
      problems << "next_pay_on must be a date (YYYY-MM-DD)" if v["next_pay_on"].present? && next_pay.nil?
      amount = money(v["typical_amount"]) if v["typical_amount"].present?
      problems << "typical_amount must be 0 or more" if v["typical_amount"].present? && (amount.nil? || amount.negative?)
      [{ "frequency" => v["frequency"], "next_pay_on" => next_pay&.iso8601, "typical_amount" => amount && format("%.2f", amount) }, problems]
    end

    def bills(value)
      return [nil, ["must be a list"]] unless value.is_a?(Array)
      return [nil, ["at most #{MAX_BILLS} bills"]] if value.size > MAX_BILLS

      problems = []
      bills = value.each_with_index.map do |raw, i|
        b = hash(raw) || {}
        name = b["name"].to_s.strip
        amount = money(b["amount"])
        day = Integer(b["day"].to_s, exception: false)
        problems << "bill #{i + 1}: name is required (at most 80 characters)" if name.empty? || name.length > 80
        problems << "bill #{i + 1}: amount must be more than 0" unless amount&.positive? && amount <= Obligation::MAX_AMOUNT
        problems << "bill #{i + 1}: day must be 1–31" unless day&.between?(1, 31)
        problems << "bill #{i + 1}: category must be a fixed category" unless Category.fixed.exists?(slug: b["category"].to_s)
        { "name" => name, "amount" => amount && format("%.2f", amount), "day" => day, "category" => b["category"].to_s,
          "detected" => b["detected"] == true || b["detected"] == "true" }
      end
      [bills, problems]
    end

    # ON2: answers to the follow-ups that were asked, each checked against
    # the options Rails offered for its slot.
    def follow_up_answers(user, answers, value)
      v = hash(value)
      return [nil, ["must be an object of slot → answer"]] if v.nil?

      asked = Array(answers["follow_ups_asked"]).map { |f| f["slot"] }
      problems = []
      out = v.each_with_object({}) do |(slot, raw), acc|
        unless asked.include?(slot)
          problems << "#{slot}: wasn't asked"
          next
        end
        case slot
        when "irregular_income_floor"
          amount = money(raw)
          if amount && !amount.negative? && amount <= Obligation::MAX_AMOUNT
            acc[slot] = format("%.2f", amount)
          else
            problems << "#{slot}: must be an amount of 0 or more"
          end
        when "goal_priority"
          order = Array(raw).map { |x| Integer(x.to_s, exception: false) }
          if order.sort == (0...Array(answers["goals"]).size).to_a
            acc[slot] = order
          else
            problems << "#{slot}: must list every goal once"
          end
        else
          allowed = FollowUps::OPTIONS.fetch(slot, []).map(&:first)
          if allowed.include?(raw.to_s)
            acc[slot] = raw.to_s
          else
            problems << "#{slot}: must be one of #{allowed.join(', ')}"
          end
        end
      end
      [out, problems]
    end

    # Each goal is checked with the G1 model's own rules (unsaved).
    def goals(user, value)
      return [nil, ["must be a list"]] unless value.is_a?(Array)
      return [nil, ["at most #{MAX_GOALS} goals"]] if value.size > MAX_GOALS

      problems = []
      goals = value.each_with_index.map do |raw, i|
        g = hash(raw) || {}
        kind = g["kind"].to_s
        unless GOAL_KINDS.include?(kind)
          problems << "goal #{i + 1}: kind must be one of #{GOAL_KINDS.join(', ')}"
          next {}
        end
        attrs = goal_attributes(kind, g)
        model = user.goals.new(attrs)
        model.validate
        model.errors.full_messages.each { |m| problems << "goal #{i + 1}: #{m}" }
        answer_shape(kind, attrs)
      end
      [goals, problems]
    end

    # Stored in the shape the app sends (kind, name, amount, date, balance,
    # apr, monthly_payment), so a resumed interview shows the same values.
    def answer_shape(kind, attrs)
      fmt = ->(v) { v.nil? ? nil : format("%.2f", v) }
      base = { "kind" => kind, "name" => attrs[:name] }
      if kind == "debt_payoff"
        base.merge("balance" => fmt.(attrs[:starting_balance]), "apr" => fmt.(attrs[:apr]), "monthly_payment" => fmt.(attrs[:monthly_payment]))
      else
        base.merge("amount" => fmt.(attrs[:target_amount]), "date" => attrs[:target_date]&.iso8601)
      end
    end

    def goal_attributes(kind, g)
      name = g["name"].to_s.strip
      case kind
      when "debt_payoff"
        { goal_type: "debt_payoff", name:, starting_balance: money(g["balance"]), apr: money(g["apr"]), monthly_payment: money(g["monthly_payment"]) }
      when "emergency_fund"
        { goal_type: "purchase", name: name.presence || "Emergency fund", target_amount: money(g["amount"]), starting_balance: BigDecimal("0") }
      else
        { goal_type: kind, name:, target_amount: money(g["amount"]), target_date: date(g["date"]), starting_balance: BigDecimal("0") }
      end
    end

    def hash(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      value.is_a?(Hash) ? value.stringify_keys : nil
    end

    def money(value)
      return nil if value.nil? || value.to_s.strip.empty?

      BigDecimal(value.to_s.delete("$,").strip)
    rescue ArgumentError
      nil
    end

    def date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
