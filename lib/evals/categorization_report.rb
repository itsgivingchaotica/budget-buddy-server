module Evals
  # EV1 (categorization eval): metrics and the Markdown report for one or
  # more runs (easy set, hard set, hard set with Claude only).
  module CategorizationReport
    # $ per million tokens (input, output), list prices noted 2026-11.
    PRICES = { "claude-haiku-5-5" => [0.10, 0.50] }.freeze
    AUTO = %w[memory rule ai].freeze
    STAGE_NAMES = { "memory" => "Merchant memory", "rule" => "Keyword rules", "ai" => "Claude" }.freeze

    Run = Data.define(:name, :about, :result)

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
        # A true transfer categorized (as spending or income) without going to
        # the user. Must be 0. The pipeline never assigns Transfers itself.
        transfer_critical: auto.count { |r| r.label == "transfers" },
        transfers_total: rows.count { |r| r.label == "transfers" },
        transfers_to_review: review.count { |r| r.label == "transfers" },
        per_category: group_stats(rows, &:label),
        per_kind: group_stats(rows, &:kind),
        mistakes: auto.reject { |r| r.predicted == r.label }
      }
    end

    def group_stats(rows, &key)
      rows.group_by(&key).sort.to_h do |k, rs|
        a = rs.select { |r| AUTO.include?(r.stage) }
        [k, { n: rs.size, auto: a.size, auto_correct: a.count { |r| r.predicted == r.label }, review: rs.size - a.size }]
      end
    end

    def stage_stats(rows) = { n: rows.size, correct: rows.count { |r| r.predicted == r.label } }

    def pct(part, whole) = whole.zero? ? "n/a" : format("%.1f%%", 100.0 * part / whole)

    def cost(result)
      input, output = PRICES[result.model] || return
      (result.input_tokens * input + result.output_tokens * output) / 1_000_000.0
    end

    def requests_text(n) = "#{n} #{n == 1 ? "request" : "requests"}"

    # runs: [Run]; meta: hard-set meta (written_on, rules_fingerprint);
    # fingerprint: the keyword rules' fingerprint now.
    def markdown(runs, meta:, fingerprint:)
      first = runs.first.result
      lines = []
      lines << "# Categorization eval (EV1): #{first.ran_at.to_date.iso8601}"
      lines << ""
      lines << "- **Run:** #{first.ran_at.utc.iso8601} · model `#{first.model}` · real pipeline (merchant memory → transfer check → keyword rules → Claude), daily AI cap in place; a separate eval user whose merchant memory is emptied before each run."
      lines << "- **Where the labels come from:** never from the pipeline's output. **Easy set:** each row's category was assigned by the demo generator when it created the row (merchant, amount and category chosen together). **Hard set:** #{runs.find { |r| r.name.start_with?("Hard") } ? "#{meta["written_by"]} wrote each row with its label on #{meta["written_on"]} (`lib/evals/golden_hard.yml`); labels are the author's judgement, and rows marked ambiguous have a defensible label where another is possible." : "not run."} The eval only compares the pipeline's output with these labels. Synthetic data only."
      lines << "- **Keyword rules:** #{rules_line(meta, fingerprint)}"
      total_in = runs.sum { |r| r.result.input_tokens }
      total_out = runs.sum { |r| r.result.output_tokens }
      total_cost = runs.sum { |r| cost(r.result).to_f }
      lines << "- **Claude usage (all runs):** #{requests_text(runs.sum { |r| r.result.requests })}, #{total_in} input + #{total_out} output tokens, about #{format("$%.4f", total_cost)} at list price."
      lines << ""
      lines << "## Headline"
      lines << ""
      lines << "| | " + runs.map(&:name).join(" | ") + " |"
      lines << "|---|" + runs.map { "---" }.join("|") + "|"
      ms = runs.map { |r| metrics(r.result) }
      lines << "| Rows | " + ms.map { |m| m[:total].to_s }.join(" | ") + " |"
      lines << "| **Accuracy of auto-categorized rows** (categories the user never checks) | " + ms.map { |m| "**#{pct(m[:auto_correct], m[:auto])}** (#{m[:auto_correct]}/#{m[:auto]})" }.join(" | ") + " |"
      lines << "| Review rate (sent to the user) | " + ms.map { |m| "#{pct(m[:review], m[:total])} (#{m[:review]})" }.join(" | ") + " |"
      lines << "| Suggestion right, when the row went to review with one | " + ms.map { |m| "#{pct(m[:suggestions_correct], m[:suggestions])} (#{m[:suggestions_correct]}/#{m[:suggestions]})" }.join(" | ") + " |"
      lines << "| **Transfer critical errors** (must be 0) | " + ms.map { |m| "**#{m[:transfer_critical]}** of #{m[:transfers_total]}" }.join(" | ") + " |"
      lines << "| Correct with no user action (auto-correct / all rows) | " + ms.map { |m| pct(m[:auto_correct], m[:total]) }.join(" | ") + " |"
      AUTO.each do |stage|
        lines << "| #{STAGE_NAMES[stage]}: rows (accuracy) | " + ms.map { |m| s = m[:by_stage][stage]; "#{s[:n]} (#{pct(s[:correct], s[:n])})" }.join(" | ") + " |"
      end
      lines << "| Claude usage | " + runs.map { |r| "#{requests_text(r.result.requests)}, #{r.result.input_tokens}+#{r.result.output_tokens} tokens" }.join(" | ") + " |"
      lines << ""
      runs.zip(ms).each { |run, m| lines.concat(section(run, m)) }
      lines.concat(limitations(runs, ms, meta, fingerprint))
      lines.join("\n")
    end

    def rules_line(meta, fingerprint)
      if fingerprint == meta["rules_fingerprint"]
        "frozen since the hard set was written (fingerprint `#{fingerprint}` matches)."
      else
        "**changed after the hard set was written** (fingerprint was `#{meta["rules_fingerprint"]}`, now `#{fingerprint}`). Hard-set results may reflect rules tuned after seeing them."
      end
    end

    def section(run, m)
      lines = ["## #{run.name}", "", run.about, ""]
      lines << "| Stage | Rows | Correct | Accuracy |"
      lines << "|---|---|---|---|"
      AUTO.each { |s| st = m[:by_stage][s]; lines << "| #{STAGE_NAMES[s]} | #{st[:n]} | #{st[:correct]} | #{pct(st[:correct], st[:n])} |" }
      lines << "| Sent to review | #{m[:review]} | with a suggestion: #{m[:suggestions]} (right: #{m[:suggestions_correct]}) | without: #{m[:review_without_suggestion]} |"
      lines << ""
      if m[:per_kind].keys != ["easy"]
        lines << "**By row kind**"
        lines << ""
        lines << "| Kind | Rows | Auto-categorized | Auto correct | Sent to review |"
        lines << "|---|---|---|---|---|"
        m[:per_kind].each { |k, c| lines << "| #{k} | #{c[:n]} | #{c[:auto]} | #{c[:auto_correct]} (#{pct(c[:auto_correct], c[:auto])}) | #{c[:review]} |" }
        lines << ""
      end
      lines << "**Per category**"
      lines << ""
      lines << "| True category | Rows | Auto-categorized | Auto correct | Sent to review |"
      lines << "|---|---|---|---|---|"
      m[:per_category].each { |k, c| lines << "| #{k} | #{c[:n]} | #{c[:auto]} | #{c[:auto_correct]} (#{pct(c[:auto_correct], c[:auto])}) | #{c[:review]} |" }
      lines << ""
      lines << "**Mistakes among auto-categorized rows**"
      lines << ""
      if m[:mistakes].empty?
        lines << "None."
      else
        lines << "| Description | True | Categorized as | Stage | Kind |"
        lines << "|---|---|---|---|---|"
        m[:mistakes].each { |r| lines << "| #{r.description.gsub("|", "/")} | #{r.label} | #{r.predicted} | #{STAGE_NAMES[r.stage]} | #{r.kind} |" }
      end
      lines << ""
      lines
    end

    def limitations(runs, ms, meta, fingerprint)
      easy = runs.index { |r| r.name.start_with?("Easy") }
      lines = ["## Limitations", ""]
      if easy
        m = ms[easy]
        lines << "- **Easy set:** the keyword rules and the demo merchants were written together (AI1 and DEMO-G), so #{m[:by_stage]["rule"][:n]} of #{m[:total]} rows hit a rule. It measures rule coverage of the demo data, not generalization."
      end
      lines << "- **Hard set:** #{runs.find { |r| r.name.start_with?("Hard") }&.result&.rows&.size || 0} rows written by the same author as the rules (deliberately using merchants and phrasings the rules don't know), labelled by judgement; ambiguous rows have more than one defensible answer. Small sample: treat percentages as indicative."
      lines << "- **Claude-only run:** keyword rules off; merchant memory empty; the transfer check stays on, because it only sends rows to review (it never categorizes), so the critical-error count stays comparable."
      lines << "- One run each; Claude's answers can vary between runs. Synthetic data only."
      lines << "- #{fingerprint == meta["rules_fingerprint"] ? "The keyword rules were not changed after the hard set was written." : "The keyword rules were changed after the hard set was written (see the top)."}"
      lines << ""
      lines
    end
  end
end
