# PL1 (plan drafting), SPEC_ONBOARDING_PLAN §7 "Adjustments before
# approval": changes to a draft only (budget amounts, bills on/off or edited,
# goals on/off or edited). Every change is checked, all or nothing; then
# PlanFigures recomputes the fit line and the G2 figures, so nothing the user
# sees is stale. Nothing live changes until PL2 (plan approval).
#
#   { budgets: [{ category:, amount: }],
#     bills:   [{ key:, included?, name?, amount?, day? }],
#     goals:   [{ key:, included?, name?, amount?, date?, balance?, apr?, monthly_payment? }] }
module PlanEdits
  class Invalid < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super("invalid plan changes")
    end
  end

  GOAL_FIELDS = %w[name amount date balance apr monthly_payment].freeze

  module_function

  def apply!(proposal, params, now: Time.current)
    payload = proposal.payload.deep_dup
    errors = {}
    budgets(payload, Array(params["budgets"]), errors)
    bills(payload, Array(params["bills"]), errors)
    goals(proposal.user, payload, Array(params["goals"]), errors)
    raise Invalid, errors if errors.any?

    proposal.update!(payload: PlanFigures.compute(proposal.user, payload, now:))
    proposal
  end

  def budgets(payload, changes, errors)
    changes.each do |raw|
      c = raw.to_h.stringify_keys
      item = payload["categories"].find { |x| x["category"] == c["category"].to_s }
      next (errors["budgets"] ||= []) << "unknown category #{c['category']}" unless item

      amount = PlanFigures.money(c["amount"])
      next (errors["budgets"] ||= []) << "#{item['category']}: amount must be 0 or more" unless amount && !amount.negative? && amount <= CategoryBudget::MAX_AMOUNT

      option = item["options"].find { |_, v| BigDecimal(v) == amount }&.first
      item.merge!("amount" => PlanFigures.money_s(amount), "option" => option || "custom", "reason" => option == item["option"] ? item["reason"] : nil)
    end
  end

  def bills(payload, changes, errors)
    changes.each do |raw|
      c = raw.to_h.stringify_keys
      item = payload["bills"].find { |x| x["key"] == c["key"].to_s }
      next (errors["bills"] ||= []) << "unknown bill #{c['key']}" unless item

      problems = []
      item["included"] = ActiveModel::Type::Boolean.new.cast(c["included"]) if c.key?("included")
      if c.key?("name")
        name = c["name"].to_s.strip
        name.empty? || name.length > 80 ? problems << "name must be 1–80 characters" : item["name"] = name
      end
      if c.key?("amount")
        amount = PlanFigures.money(c["amount"])
        amount&.positive? && amount <= Obligation::MAX_AMOUNT ? item["amount"] = PlanFigures.money_s(amount) : problems << "amount must be more than 0"
      end
      if c.key?("day")
        day = Integer(c["day"].to_s, exception: false)
        day&.between?(1, 31) ? item["day"] = day : problems << "day must be 1–31"
      end
      (errors["bills"] ||= []).concat(problems.map { |p| "#{item['key']}: #{p}" }) if problems.any?
    end
  end

  def goals(user, payload, changes, errors)
    changes.each do |raw|
      c = raw.to_h.stringify_keys
      item = payload["goals"].find { |x| x["key"] == c["key"].to_s }
      next (errors["goals"] ||= []) << "unknown goal #{c['key']}" unless item

      item["included"] = ActiveModel::Type::Boolean.new.cast(c["included"]) if c.key?("included")
      edited = item.merge(c.slice(*GOAL_FIELDS).transform_values { |v| v.nil? ? nil : v.to_s })
      record = PlanFigures.goal_record(user, edited)
      if record.valid?
        item.merge!(Onboarding::Interview.answer_shape(item["kind"], Onboarding::Interview.goal_attributes(item["kind"], edited)))
      else
        (errors["goals"] ||= []).concat(record.errors.full_messages.map { |m| "#{item['key']}: #{m}" })
      end
    end
  end
end
