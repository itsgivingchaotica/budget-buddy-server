module Evals
  # PL1 (plan drafting) eval: builds N drafts for one user through the real
  # PlanDrafter (real Claude calls, the daily AI cap in place) and reports how
  # often Rails had to use the fallback, and which checks failed, by the
  # generic codes the draft records. Synthetic demo data only. Never the
  # model's text in the report: intro lengths are counted, not quoted.
  module PlanDrafting
    TARGET_FALLBACK_RATE = 0.10

    module_function

    def run(user, runs:, now: Time.current)
      usage_before = usage(user, now)
      drafts = Array.new(runs) { PlanDrafter.call(user, now:) }
      usage_after = usage(user, now)
      { ran_at: now.utc, runs:, drafts:, answers: user.financial_profile.answers,
        usage: usage_after.zip(usage_before).map { |a, b| a - b } }
    end

    def usage(user, now)
      row = AiUsage.find_by(user:, day: now.utc.to_date, feature: "plan")
      row ? [row.requests, row.input_tokens, row.output_tokens] : [0, 0, 0]
    end

    def metrics(result)
      drafts = result[:drafts]
      tries = drafts.map { |d| Array(d.payload.dig("checks", "tries")) }
      { runs: drafts.size,
        fallback: drafts.count { |d| d.source == "fallback" },
        first_try: drafts.zip(tries).count { |d, t| d.source == "model" && t.size == 1 },
        after_retry: drafts.zip(tries).count { |d, t| d.source == "model" && t.size == 2 },
        errors: drafts.filter_map { |d| d.payload.dig("checks", "error") }.tally,
        codes: tries.flatten(1).flatten.tally.sort_by { |code, n| [-n, code] },
        codes_in_fallbacks: drafts.zip(tries).select { |d, _| d.source == "fallback" }.flat_map { |_, t| t.flatten }.tally.sort_by { |c, n| [-n, c] },
        trims: drafts.select { |d| d.source == "model" }.map { |d| d.payload["categories"].count { |c| c["option"] != "keep" } },
        intro_lengths: drafts.select { |d| d.source == "model" }.map { |d| d.payload["intro"].to_s.length } }
    end

    def pct(n, d) = d.zero? ? "n/a" : format("%.0f%%", 100.0 * n / d)

    def markdown(result, intro_max:)
      m = metrics(result)
      requests, input, output = result[:usage]
      model = result[:drafts].filter_map(&:model).first || "claude-haiku-5-5"
      price_in, price_out = CategorizationReport::PRICES[model] || [nil, nil]
      cost = price_in && ((input * price_in) + (output * price_out)) / 1_000_000.0
      a = result[:answers]
      goals = Array(a["goals"])
      rate = m[:runs].zero? ? 0 : m[:fallback].to_f / m[:runs]
      lines = []
      lines << "# Plan drafting eval (PL1): #{result[:ran_at].to_date.iso8601}"
      lines << ""
      lines << "**Status:** Eval report (Builder, #{result[:ran_at].to_date.iso8601}) · written by `bin/rails eval:plan_drafting`"
      lines << ""
      lines << "- **Run:** #{result[:ran_at].iso8601} · model `#{model}` · real `PlanDrafter` (one call, Rails' checks, one retry, then the fallback), daily AI cap in place · #{m[:runs]} drafts."
      lines << "- **Data:** the synthetic demo user (`demo:seed`), #{result[:drafts].first&.payload&.dig('months')} covered months; answers: pay #{a.dig('pay', 'frequency')}, " \
               "side income #{a['side_income']}, #{Array(a['bills']).size} bills, #{goals.size} goals (#{goals.count { |g| g['date'].blank? && g['kind'] != 'debt_payoff' }} without a date), " \
               "appetite \"#{a['change_appetite']}\". The same answers for every draft, so differences come from the model."
      lines << "- **Limits checked:** intro ≤ #{intro_max} characters, reasons ≤ #{PlanDrafter::REASON_MAX}, no digits, every category once with a real option, ≤ #{PlanDrafter::MAX_TRIMS} trims and no stretch for small trims, at least one change (D-034); all stated in the request."
      lines << "- **Claude usage:** #{requests} requests, #{input} input + #{output} output tokens#{cost ? format(', about $%.4f at list price', cost) : ''}."
      lines << ""
      lines << "## Headline"
      lines << ""
      lines << "| | Drafts | Share |"
      lines << "|---|---|---|"
      lines << "| **Fallback** (target < #{(TARGET_FALLBACK_RATE * 100).round}%) | **#{m[:fallback]}** | **#{pct(m[:fallback], m[:runs])}** |"
      lines << "| Model's answer passed on the first try | #{m[:first_try]} | #{pct(m[:first_try], m[:runs])} |"
      lines << "| Passed after the one retry | #{m[:after_retry]} | #{pct(m[:after_retry], m[:runs])} |"
      lines << ""
      lines << "**Result:** #{rate < TARGET_FALLBACK_RATE ? 'meets' : 'misses'} the target."
      lines << ""
      lines << "## Failed checks (generic codes, every try)"
      lines << ""
      if m[:codes].empty? && m[:errors].empty?
        lines << "None: every try passed."
      else
        lines << "| Code | Tries | In drafts that fell back |"
        lines << "|---|---|---|"
        fallback_codes = m[:codes_in_fallbacks].to_h
        m[:codes].each { |code, n| lines << "| `#{code}` | #{n} | #{fallback_codes.fetch(code, 0)} |" }
        m[:errors].each { |code, n| lines << "| error `#{code}` | #{n} | #{n} |" }
      end
      lines << ""
      lines << "## The model's drafts"
      lines << ""
      if m[:intro_lengths].any?
        lines << "- Intro length: #{m[:intro_lengths].min}–#{m[:intro_lengths].max} characters (mean #{(m[:intro_lengths].sum.to_f / m[:intro_lengths].size).round})."
        lines << "- Categories changed (trim or stretch) per draft: #{m[:trims].tally.sort.map { |k, v| "#{k} in #{v}" }.join(', ')}."
      else
        lines << "- No draft used the model's answer."
      end
      lines << ""
      lines << "## Limitations"
      lines << ""
      lines << "- One user and one set of answers; other appetites (keep, push) and other data aren't covered by this run."
      lines << "- #{m[:runs]} drafts is a small sample: one fallback moves the rate by #{pct(1, m[:runs])}."
      lines << "- The report counts checks, not tone; tone was reviewed by the Planner on the sample draft (D-034)."
      lines.join("\n") + "\n"
    end
  end
end
