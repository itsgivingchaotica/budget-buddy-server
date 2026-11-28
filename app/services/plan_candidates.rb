# PL1 (plan drafting), SPEC_ONBOARDING_PLAN §6.1: the budget options Rails
# offers for each flexible category. Deterministic; the model only chooses
# among these (D-027).
#
#   usual    AN1's median of monthly spending over the last up to 6 full
#            months the data covers (current month, transfers and
#            uncategorized rows excluded)
#   keep     usual rounded UP to $5
#   trim     90% of usual rounded to the nearest $5, only if at least $5 below keep
#   stretch  80% of usual rounded to the nearest $5, only for "Push me a bit",
#            never for essentials (Groceries, Healthcare, Transportation), and
#            only if at least $5 below the next option up
#   fewer than 2 full months → keep only, marked new
#
# The ON2 follow-up `biggest_trim_ok` narrows the top category (the largest
# usual, as ON2 chose it): "Leave it alone" → keep only; "A little" → no stretch.
module PlanCandidates
  ESSENTIAL = %w[groceries healthcare transportation].freeze
  TRIM = BigDecimal("0.9")
  STRETCH = BigDecimal("0.8")
  STEP = BigDecimal("5")
  MIN_MONTHS = 2

  module_function

  def call(user, answers)
    averages = SpendingAnalytics.category_averages(user, months: 6)
    appetite = answers["change_appetite"].presence || "trim"
    trim_ok = answers.dig("follow_ups", "biggest_trim_ok")
    usable = averages[:categories].select { |c| c[:median]&.positive? }
    top = usable.max_by { |c| c[:median] }&.dig(:category)
    months = averages[:months_covered].size

    categories = usable.map do |c|
      limit = c[:category] == top ? trim_ok : nil
      { category: c[:category], name: c[:name], essential: ESSENTIAL.include?(c[:category]),
        usual: c[:median], new: months < MIN_MONTHS,
        options: options(c[:median], appetite:, essential: ESSENTIAL.include?(c[:category]), months:, limit:) }
    end
    { months:, months_covered: averages[:months_covered], categories:,
      uncategorized_excluded: averages[:uncategorized_excluded] }
  end

  def options(usual, appetite:, essential:, months:, limit: nil)
    keep = round_up(usual)
    result = { "keep" => keep }
    return result if months < MIN_MONTHS || limit == "leave_it"

    trim = round_nearest(usual * TRIM)
    result["trim"] = trim if trim <= keep - STEP
    return result unless appetite == "push" && !essential && limit != "a_little"

    stretch = round_nearest(usual * STRETCH)
    result["stretch"] = stretch if stretch <= result.fetch("trim", keep) - STEP
    result
  end

  def round_up(amount) = ((amount / STEP).ceil * STEP).to_d
  def round_nearest(amount) = ((amount / STEP).round(0, BigDecimal::ROUND_HALF_UP) * STEP).to_d
end
