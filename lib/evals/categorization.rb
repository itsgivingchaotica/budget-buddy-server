module Evals
  # EV1 (categorization eval), plan D-016 / handoff #05 §D: runs the golden
  # set through the real categorization pipeline and measures it.
  #
  # Labels: each golden row's expected category comes from the golden set
  # itself (see GoldenSets): the demo generator's category for the easy set,
  # the hand-written label for the hard set. The eval never derives a label
  # from the pipeline's output; it only compares that output to the labels.
  #
  # Setup: a separate eval user (never the demo account or a real login),
  # wiped first so merchant memory starts empty, with one account per
  # account purpose in the golden set. The golden rows are inserted as
  # transactions, then Categorization::Pipeline runs until nothing is left for
  # Claude (memory -> transfer check -> keyword rules -> Claude). Claude calls
  # go through AnthropicClient, so the daily AI cap applies (per user).
  class Categorization
    EMAIL = "eval.user@example.com".freeze
    ACCOUNTS = {
      "spending" => { name: "Eval Everyday", kind: "checking" },
      "savings" => { name: "Eval Savings", kind: "savings" },
      "side_income" => { name: "Eval Side Income", kind: "p2p" },
      "bills" => { name: "Eval Bills", kind: "checking" },
      "other" => { name: "Eval Other", kind: "other" }
    }.freeze
    MAX_RUNS = 10

    # One golden row's outcome. stage: "memory" | "rule" | "ai" (categorized
    # without the user) or "review" (sent to the user). predicted: the
    # category slug the pipeline set, or for review rows the suggestion (if
    # any). label: the golden set's true slug. kind: easy, or the hard-set
    # row kind (unknown_merchant, messy, p2p, refund, ambiguous, transfer).
    Row = Data.define(:label, :kind, :description, :amount, :purpose, :stage, :predicted, :suggestion, :transfer_like)

    Result = Data.define(:rows, :model, :requests, :input_tokens, :output_tokens, :ran_at, :keyword_rules)

    # golden: GoldenSets::Row list (easy or hard). keyword_rules: false runs
    # the pipeline with the keyword rules switched off (Claude-only run).
    def self.run(env: Rails.env, ai: nil, golden: GoldenSets.easy, keyword_rules: true)
      new(env:, ai:, golden:, keyword_rules:).run
    end

    def initialize(env:, ai:, golden:, keyword_rules:)
      raise ArgumentError, "the eval runs only in development or test" unless %w[development test].include?(env.to_s)

      @ai = ai
      @golden = golden
      @keyword_rules = keyword_rules
    end

    def run
      user = User.find_or_create_by!(email: EMAIL) { |u| u.assign_attributes(first_name: "Eval", last_name: "User") }
      Demo::Reset.call(env: "development", email: EMAIL) # wipe the eval user only; memory starts empty
      accounts = ACCOUNTS.to_h do |purpose, attrs|
        [purpose, user.accounts.find_by(name: attrs[:name]) || user.accounts.create!(attrs.merge(purpose:))]
      end

      golden = @golden
      ids = insert(golden, accounts)
      before = usage(user)

      MAX_RUNS.times do
        break if ::Categorization::Pipeline.call(user:, scope: user.transactions, ai: @ai, keyword_rules: @keyword_rules).remaining.zero?
      end

      after = usage(user)
      rows = collect(golden, ids)
      Result.new(
        rows:, model: AnthropicClient.model_for(:categorization),
        requests: after[0] - before[0], input_tokens: after[1] - before[1], output_tokens: after[2] - before[2],
        ran_at: Time.current, keyword_rules: @keyword_rules
      )
    end

    private

    # Returns transaction ids in golden order. Identical rows (same account,
    # date, amount and cleaned description) get occurrence 1, 2, ... as an
    # import would number them.
    def insert(golden, accounts)
      seen = Hash.new(0)
      golden.map do |g|
        account = accounts.fetch(g.purpose)
        description = g.description.gsub(/\s+/, " ").strip
        amount = BigDecimal(g.cents) / 100
        key = [account.id, Transaction.duplicate_key_for(posted_on: g.date, amount:, normalized_description: Transaction.normalize_description(description))]
        account.transactions.create!(posted_on: g.date, amount:, description:, occurrence: (seen[key] += 1)).id
      end
    end

    def collect(golden, ids)
      txns = Transaction.where(id: ids).includes(:category, :suggested_category, :account).index_by(&:id)
      golden.zip(ids).map do |g, id|
        t = txns.fetch(id)
        auto = t.category_id.present? && !t.needs_review
        Row.new(
          label: g.label, kind: g.kind, description: t.description, amount: t.amount, purpose: t.account.purpose,
          stage: auto ? t.categorization_source : "review",
          predicted: auto ? t.category.slug : t.suggested_category&.slug,
          suggestion: t.suggested_category&.slug,
          transfer_like: ::Categorization::TransferCheck.transfer_like?(::Categorization::MerchantKey.for(t.normalized_description))
        )
      end
    end

    def usage(user)
      scope = AiUsage.where(user:, feature: "categorize")
      [scope.sum(:requests), scope.sum(:input_tokens), scope.sum(:output_tokens)]
    end
  end
end
