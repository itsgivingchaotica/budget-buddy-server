module Evals
  # EV1 (categorization eval): metrics and the Markdown report.
  module CategorizationReport
    # $ per million tokens (input, output), list prices noted 2026-11.
    PRICES = { "claude-haiku-5-5" => [0.10, 0.50] }.freeze
    AUTO = %w[memory rule ai].freeze

    module_function

    def metrics(result)
      rows = result.rows
      auto = rows.select { |r| AUTO.include?(r.stage) }
      review = rows.select { |r| r.stage == "review" }
      with_suggestion = review.select(&:suggestion)
      {
        total: rows.size,
        auto: auto.size,
        auto_correct: auto.count { |r| r.predicted == r.label },
        review: review.size,
        by_stage: AUTO.to_h { |s| [s, stage_stats(auto.select { |r| r.stage == s })] },
        suggestions: with_suggestion.size,
        suggestions_correct: with_suggestion.count { |r| r.suggestion == r.label },
        review_without_suggestion: review.size - with_suggestion.size,
        # A true transfer that was categorized (as spending or income) without
        # going to the user: must be 0. The pipeline never assigns Transfers.
        transfer_critical: auto.count { |r| r.label == "transfers" },
        transfers_total: rows.count { |r| r.label == "transfers" },
        transfers_to_review: review.count { |r| r.label == "transfers" },
        per_category: rows.group_by(&:label).sort.to_h do |label, rs|
          a = rs.select { |r| AUTO.include?(r.stage) }
          [label, { n: rs.size, auto: a.size, auto_correct: a.count { |r| r.predicted == r.label }, review: rs.size - a.size }]
        end,
        confusions: auto.reject { |r| r.predicted == r.label }.map { |r| [r.label, r.predicted, r.stage] }.tally
                        .sort_by { |(_, n)| -n }.to_h
      }
    end

    # What this run can and can't tell us (numbers filled in from the run).
    def limitations(m)
      rules = m[:by_stage]["rule"][:n]
      claude = m[:by_stage]["ai"][:n]
      [
        "## Limitations",
        "",
        "- **The keyword rules and the golden merchants were written together** (AI1 and DEMO-G), so #{rules} of #{m[:total]} rows were matched by a rule. " \
        "High rule accuracy here shows the rules cover the demo data, not that they generalize to real bank exports.",
        "- **Claude saw few rows:** it categorized #{claude} and suggested #{m[:suggestions]} more. That is too small a sample to estimate Claude's accuracy; " \
        "a harder golden set (merchants the rules don't know, ambiguous and noisy descriptions) is needed for that.",
        "- **Some labels are judgement calls** (e.g. \"other\" for marketplaces such as Amazon or Target); those rows are expected to go to review.",
        "- Synthetic data only; one run (Claude's answers can vary between runs).",
        ""
      ]
    end

    def stage_stats(rows) = { n: rows.size, correct: rows.count { |r| r.predicted == r.label } }

    def pct(part, whole) = whole.zero? ? "n/a" : format("%.1f%%", 100.0 * part / whole)

    def cost(result)
      input, output = PRICES[result.model] || return
      (result.input_tokens * input + result.output_tokens * output) / 1_000_000.0
    end

    def markdown(result)
      m = metrics(result)
      usd = cost(result)
      lines = []
      lines << "# Categorization eval (EV1): #{result.ran_at.to_date.iso8601}"
      lines << ""
      lines << "- **Run:** #{result.ran_at.utc.iso8601} · model `#{result.model}` · golden set of #{m[:total]} synthetic rows (Demo::Generator seed #{result.seed}, end date #{result.end_on})"
      lines << "- **Where the labels come from:** each row's expected category is the one the demo generator assigned when it created the row (merchant, amount and category are chosen together, before any categorization). The eval never takes a label from the pipeline's output; it only compares that output with the generator's labels. No real data is used."
      lines << "- **Setup:** a separate eval user with empty merchant memory; the real pipeline (merchant memory → transfer check → keyword rules → Claude), with the daily AI cap in place."
      lines << "- **Claude usage:** #{result.requests} #{result.requests == 1 ? "request" : "requests"}, #{result.input_tokens} input + #{result.output_tokens} output tokens#{usd ? format(", about $%.4f at list price", usd) : ""}."
      lines << ""
      lines << "## Headline"
      lines << ""
      lines << "| Metric | Value |"
      lines << "|---|---|"
      lines << "| **Accuracy of auto-categorized rows** (categories the user never checks) | **#{pct(m[:auto_correct], m[:auto])}** (#{m[:auto_correct]} of #{m[:auto]}) |"
      lines << "| Review rate (sent to the user) | #{pct(m[:review], m[:total])} (#{m[:review]} of #{m[:total]}) |"
      lines << "| **Transfer critical errors** (a transfer categorized as spending or income without review; must be 0) | **#{m[:transfer_critical]}** |"
      lines << "| Transfers sent to review instead (for transfer matching) | #{m[:transfers_to_review]} of #{m[:transfers_total]} |"
      lines << "| Correct without any user action (auto-correct / all rows) | #{pct(m[:auto_correct], m[:total])} |"
      lines << ""
      lines << "## By stage (auto-categorized rows)"
      lines << ""
      lines << "| Stage | Rows | Correct | Accuracy |"
      lines << "|---|---|---|---|"
      m[:by_stage].each { |stage, s| lines << "| #{{ "memory" => "Merchant memory", "rule" => "Keyword rules", "ai" => "Claude" }[stage]} | #{s[:n]} | #{s[:correct]} | #{pct(s[:correct], s[:n])} |" }
      lines << ""
      lines << "## Rows sent to review"
      lines << ""
      lines << "| | Rows |"
      lines << "|---|---|"
      lines << "| Sent to review | #{m[:review]} |"
      lines << "| … with a suggestion (\"Category?\") | #{m[:suggestions]} (suggestion right: #{pct(m[:suggestions_correct], m[:suggestions])}) |"
      lines << "| … without a suggestion | #{m[:review_without_suggestion]} |"
      lines << ""
      lines << "## Per category"
      lines << ""
      lines << "| True category | Rows | Auto-categorized | Auto correct | Sent to review |"
      lines << "|---|---|---|---|---|"
      m[:per_category].each { |label, c| lines << "| #{label} | #{c[:n]} | #{c[:auto]} | #{c[:auto_correct]} (#{pct(c[:auto_correct], c[:auto])}) | #{c[:review]} |" }
      lines << ""
      lines.concat(limitations(m))
      lines << "## Mistakes among auto-categorized rows"
      lines << ""
      if m[:confusions].empty?
        lines << "None."
      else
        lines << "| True category | Categorized as | Stage | Rows |"
        lines << "|---|---|---|---|"
        m[:confusions].each { |(label, predicted, stage), n| lines << "| #{label} | #{predicted} | #{stage} | #{n} |" }
      end
      lines << ""
      lines.join("\n")
    end
  end
end
