require "test_helper"

# EV1 (categorization eval): the golden sets, the runner (with a fake AI, no
# API calls) and the report.
class Evals::CategorizationTest < ActiveSupport::TestCase
  # Answers every item it's sent with one fixed category.
  class FixedAi
    attr_reader :items_seen

    def initialize(slug, confidence) = (@slug, @confidence, @items_seen = slug, confidence, 0)

    def categorize(items:, allowed_slugs:)
      @items_seen += items.size
      items.map { |i| { index: i[:index], category_slug: @slug, confidence: @confidence } }
    end
  end

  Row = Evals::Categorization::Row
  Run = Evals::CategorizationReport::Run

  def row(label, stage, predicted, suggestion: nil, kind: "easy")
    Row.new(label:, kind:, description: "X", amount: BigDecimal("-1"), purpose: "spending", stage:, predicted:, suggestion:, transfer_like: false)
  end

  def result(rows, input: 0, output: 0, requests: 1)
    Evals::Categorization::Result.new(rows:, model: "claude-haiku-5-5", requests:, input_tokens: input, output_tokens: output,
                                      ran_at: Time.utc(2026, 11, 26, 12), keyword_rules: true)
  end

  def meta = { "written_on" => "2026-11-26", "written_by" => "Claude Code", "rules_fingerprint" => "abc" }

  setup { Rails.application.load_seed }

  # --- golden sets -------------------------------------------------------------

  test "easy-set labels are the generator's categories; hard-set labels are the file's" do
    assert_equal Demo::Generator.new.golden.map(&:slug), Evals::GoldenSets.easy.map(&:label)
    hard = Evals::GoldenSets.hard
    raw = YAML.load_file(Evals::GoldenSets::HARD_PATH, permitted_classes: [Date])["rows"]
    assert_equal raw.map { |r| r["label"] }, hard.map(&:label)
    assert_operator hard.size, :>=, 60
    assert_empty hard.map(&:label).uniq - Category.active_list.pluck(:slug), "every hard label is a real category"
    assert_equal %w[ambiguous messy p2p refund transfer unknown_merchant], hard.map(&:kind).uniq.sort
  end

  test "the keyword rules are frozen at the fingerprint recorded with the hard set" do
    assert Evals::GoldenSets.rules_frozen?, "rules changed after the hard set was written: update the report note, not the fingerprint"
  end

  test "the hard set contains no real personal data" do
    text = File.read(Evals::GoldenSets::HARD_PATH)
    assert_no_match(/@|https?:|\b\d{3}-\d{2}-\d{4}\b|\d{3}[-. ]\d{3}[-. ]\d{4}/, text)
  end

  # --- runner --------------------------------------------------------------------

  test "labels come from the golden set, whatever the pipeline answers" do
    golden = Evals::GoldenSets.easy
    res = Evals::Categorization.run(env: "test", ai: FixedAi.new("gifts", 0.95), golden:)
    assert_equal golden.map(&:label), res.rows.map(&:label)
    ai_rows = res.rows.select { |r| r.stage == "ai" }
    assert ai_rows.any?
    assert ai_rows.all? { |r| r.predicted == "gifts" }, "the pipeline's output is the prediction, never the label"
  end

  test "transfers are never auto-categorized by the full pipeline, even by an AI answering Income" do
    ai = FixedAi.new("income", 0.99)
    m = Evals::CategorizationReport.metrics(Evals::Categorization.run(env: "test", ai:))
    assert_equal 0, m[:transfer_critical]
    assert_operator ai.items_seen, :>, 0
  end

  test "the hard set's unguarded transfers reach the AI, so a careless AI shows up as critical errors" do
    m = Evals::CategorizationReport.metrics(
      Evals::Categorization.run(env: "test", ai: FixedAi.new("income", 0.99), golden: Evals::GoldenSets.hard)
    )
    assert_equal 2, m[:transfer_critical], "WEB XFER and SAVINGS SWEEP bypass the transfer check"
    assert_equal 6, m[:transfers_total]
  end

  test "with keyword rules off, rule-matched rows go to the AI instead" do
    hard = Evals::GoldenSets.hard
    on = Evals::Categorization.run(env: "test", ai: FixedAi.new("other", 0.3), golden: hard)
    off_ai = FixedAi.new("other", 0.3)
    off = Evals::Categorization.run(env: "test", ai: off_ai, golden: hard, keyword_rules: false)
    assert on.rows.any? { |r| r.stage == "rule" }
    assert_equal 0, off.rows.count { |r| r.stage == "rule" }
    assert_equal false, off.keyword_rules
    assert_operator off_ai.items_seen, :>, on.rows.count { |r| r.stage == "review" } - 4
  end

  test "the eval user starts with empty memory each run, and other users are untouched" do
    eval_user = User.find_or_create_by!(email: Evals::Categorization::EMAIL) { |u| u.assign_attributes(first_name: "Eval", last_name: "User") }
    others = Transaction.where.not(account_id: eval_user.accounts.select(:id)).count
    Evals::Categorization.run(env: "test", ai: FixedAi.new("other", 0.3))
    eval_user.merchant_rules.create!(merchant_key: "WHOLEFDS MKT", category: Category.find_by!(slug: "dining-out"))
    res = Evals::Categorization.run(env: "test", ai: FixedAi.new("other", 0.3))
    assert_equal 0, res.rows.count { |r| r.stage == "memory" }, "memory was wiped before the second run"
    assert_equal 300, eval_user.transactions.count
    assert_equal others, Transaction.where.not(account_id: eval_user.accounts.select(:id)).count
  end

  test "refuses to run in production" do
    assert_raises(ArgumentError) { Evals::Categorization.run(env: "production") }
  end

  # --- metrics and report -----------------------------------------------------------

  test "metrics: auto accuracy, by stage, review, suggestions, per category and kind, mistakes" do
    rows = [
      row("groceries", "rule", "groceries"), row("groceries", "rule", "dining-out", kind: "messy"),
      row("dining-out", "ai", "dining-out"), row("rent", "memory", "rent"),
      row("other", "review", "other", suggestion: "other"), row("gifts", "review", "income", suggestion: "income"),
      row("travel", "review", nil)
    ]
    m = Evals::CategorizationReport.metrics(result(rows))
    assert_equal [7, 4, 3, 3], m.values_at(:total, :auto, :auto_correct, :review)
    assert_equal({ "memory" => { n: 1, correct: 1 }, "rule" => { n: 2, correct: 1 }, "ai" => { n: 1, correct: 1 } }, m[:by_stage])
    assert_equal [2, 1, 1], m.values_at(:suggestions, :suggestions_correct, :review_without_suggestion)
    assert_equal({ n: 2, auto: 2, auto_correct: 1, review: 0 }, m[:per_category]["groceries"])
    assert_equal({ n: 1, auto: 1, auto_correct: 0, review: 0 }, m[:per_kind]["messy"])
    assert_equal [%w[groceries dining-out rule]], m[:mistakes].map { |r| [r.label, r.predicted, r.stage] }
  end

  test "a transfer categorized without review counts as a critical error" do
    m = Evals::CategorizationReport.metrics(result([row("transfers", "memory", "groceries"), row("transfers", "review", nil)]))
    assert_equal [1, 2, 1], m.values_at(:transfer_critical, :transfers_total, :transfers_to_review)
  end

  test "the report compares the runs and states labels, rules freeze, model, date, tokens and cost" do
    runs = [
      Run.new(name: "Easy set (demo generator)", about: "easy", result: result([row("groceries", "rule", "groceries")], input: 20_000, output: 6_000)),
      Run.new(name: "Hard set", about: "hard", result: result([row("gifts", "ai", "other", kind: "p2p")], input: 1000, output: 100)),
      Run.new(name: "Hard set, Claude only", about: "claude", result: result([row("gifts", "review", nil, kind: "p2p")], requests: 2))
    ]
    md = Evals::CategorizationReport.markdown(runs, meta:, fingerprint: "abc")
    assert_includes md, "# Categorization eval (EV1): 2026-11-26"
    assert_includes md, "**Where the labels come from:** never from the pipeline's output"
    assert_includes md, "frozen since the hard set was written (fingerprint `abc` matches)"
    assert_includes md, "model `claude-haiku-5-5`"
    assert_includes md, "4 requests, 21000 input + 6100 output tokens, about $0.0052"
    assert_includes md, "| | Easy set (demo generator) | Hard set | Hard set, Claude only |"
    assert_includes md, "**100.0%** (1/1) | **0.0%** (0/1) | **n/a** (0/0)"
    assert_includes md, "| gifts | other | Claude | p2p |"
    assert_includes md, "**By row kind**"
    assert_includes md, "## Limitations"
  end

  test "the report says so when the rules changed after the hard set was written" do
    runs = [Run.new(name: "Hard set", about: "hard", result: result([row("gifts", "ai", "gifts")]))]
    md = Evals::CategorizationReport.markdown(runs, meta:, fingerprint: "def")
    assert_includes md, "**changed after the hard set was written** (fingerprint was `abc`, now `def`)"
  end
end
