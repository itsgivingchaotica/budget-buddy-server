require "test_helper"

# EV1 (categorization eval): the runner (with a fake AI, no API calls) and
# the metrics.
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

  def row(label, stage, predicted, suggestion: nil)
    Row.new(label:, description: "X", amount: BigDecimal("-1"), purpose: "spending", stage:, predicted:, suggestion:, transfer_like: false)
  end

  def result(rows, input: 0, output: 0)
    Evals::Categorization::Result.new(rows:, model: "claude-haiku-5-5", requests: 1, input_tokens: input, output_tokens: output,
                                      ran_at: Time.utc(2026, 11, 25, 12), seed: 1, end_on: Date.new(2026, 11, 20))
  end

  setup { Rails.application.load_seed }

  test "labels are the generator's true categories, whatever the pipeline answers" do
    generator = Demo::Generator.new
    # An AI that is confidently wrong about everything it sees.
    res = Evals::Categorization.run(env: "test", ai: FixedAi.new("gifts", 0.95), generator:)
    assert_equal generator.golden.map(&:slug), res.rows.map(&:label)
    assert_equal 300, res.rows.size
    ai_rows = res.rows.select { |r| r.stage == "ai" }
    assert ai_rows.any?
    assert ai_rows.all? { |r| r.predicted == "gifts" }, "the pipeline's output is recorded as the prediction, not the label"
  end

  test "transfers are never auto-categorized, even by an AI that confidently answers Income" do
    ai = FixedAi.new("income", 0.99)
    m = Evals::CategorizationReport.metrics(Evals::Categorization.run(env: "test", ai:))
    assert_equal 0, m[:transfer_critical]
    assert_equal m[:transfers_total], m[:transfers_to_review]
    assert_operator ai.items_seen, :>, 0
  end

  test "the eval user starts with empty memory each run, and other users are untouched" do
    others = Transaction.where.not(account_id: User.find_or_create_by!(email: Evals::Categorization::EMAIL) { |u|
      u.first_name = "Eval"
      u.last_name = "User"
    }.accounts.select(:id)).count
    Evals::Categorization.run(env: "test", ai: FixedAi.new("other", 0.3))
    eval_user = User.find_by!(email: Evals::Categorization::EMAIL)
    eval_user.merchant_rules.create!(merchant_key: "WHOLEFDS MKT", category: Category.find_by!(slug: "dining-out"))
    res = Evals::Categorization.run(env: "test", ai: FixedAi.new("other", 0.3))
    assert_equal 0, res.rows.count { |r| r.stage == "memory" }, "memory was wiped before the second run"
    assert_equal 300, eval_user.transactions.count
    assert_equal others, Transaction.where.not(account_id: eval_user.accounts.select(:id)).count
  end

  test "refuses to run in production" do
    assert_raises(ArgumentError) { Evals::Categorization.run(env: "production") }
  end

  test "metrics: auto accuracy, by stage, review rate, suggestions, per category, confusions" do
    rows = [
      row("groceries", "rule", "groceries"), row("groceries", "rule", "dining-out"),
      row("dining-out", "ai", "dining-out"), row("rent", "memory", "rent"),
      row("other", "review", "other", suggestion: "other"), row("gifts", "review", "income", suggestion: "income"),
      row("travel", "review", nil)
    ]
    m = Evals::CategorizationReport.metrics(result(rows))
    assert_equal [7, 4, 3, 3], m.values_at(:total, :auto, :auto_correct, :review)
    assert_equal({ "memory" => { n: 1, correct: 1 }, "rule" => { n: 2, correct: 1 }, "ai" => { n: 1, correct: 1 } }, m[:by_stage])
    assert_equal [2, 1, 1], m.values_at(:suggestions, :suggestions_correct, :review_without_suggestion)
    assert_equal({ n: 2, auto: 2, auto_correct: 1, review: 0 }, m[:per_category]["groceries"])
    assert_equal({ %w[groceries dining-out rule] => 1 }, m[:confusions])
  end

  test "a transfer categorized without review counts as a critical error" do
    m = Evals::CategorizationReport.metrics(result([row("transfers", "memory", "groceries"), row("transfers", "review", nil)]))
    assert_equal [1, 2, 1], m.values_at(:transfer_critical, :transfers_total, :transfers_to_review)
  end

  test "the report states where labels come from, the model, date, tokens and cost" do
    md = Evals::CategorizationReport.markdown(result([row("groceries", "rule", "groceries")], input: 20_000, output: 6_000))
    assert_includes md, "# Categorization eval (EV1): 2026-11-25"
    assert_includes md, "**Where the labels come from:**"
    assert_includes md, "never takes a label from the pipeline's output"
    assert_includes md, "model `claude-haiku-5-5`"
    assert_includes md, "20000 input + 6000 output tokens, about $0.0050"
    assert_includes md, "**Accuracy of auto-categorized rows** (categories the user never checks) | **100.0%**"
    assert_includes md, "**Transfer critical errors**"
    assert_includes md, "## Limitations"
    assert_includes md, "1 request,"
  end
end
