require "test_helper"

# AI1 (rules-based categorization): memory -> keyword rules -> AI (fake here).
class Categorization::PipelineTest < ActiveSupport::TestCase
  class FakeAi
    attr_reader :calls

    def initialize(&answer)
      @answer = answer || ->(_items) { [] }
      @calls = []
    end

    def categorize(items:, allowed_slugs:)
      @calls << { items:, allowed_slugs: }
      @answer.call(items)
    end
  end

  SLUGS = {
    "groceries" => "spending", "dining-out" => "spending", "transportation" => "spending",
    "subscriptions" => "spending", "debt-payments" => "spending", "income" => "income", "transfers" => "transfer"
  }.freeze

  setup do
    transactions(:one_coffee).destroy! # keep counts to the rows each test creates
    @user = users(:one)
    @account = accounts(:one_checking)
    @cat = SLUGS.each_with_index.to_h do |(slug, kind), i|
      [slug, Category.create!(name: slug.titleize, slug:, kind:, active: true, position: i + 1,
                              fixed_variable: (kind == "spending" ? "variable" : nil))]
    end
  end

  def txn(description, amount = "-10.00", account: @account, **attrs)
    account.transactions.create!({ posted_on: Date.new(2026, 11, 2), amount:, description: }.merge(attrs))
  end

  def run_pipeline(ai: FakeAi.new, scope: @user.transactions)
    Categorization::Pipeline.call(user: @user, scope:, ai:)
  end

  test "keyword rules categorize known merchants with source rule" do
    grocer = txn("WHOLEFDS MKT #10234")
    coffee = txn("SQ *STARBUCKS 08812")
    summary = run_pipeline
    assert_equal [@cat["groceries"].id, "rule", nil, false], grocer.reload.then { |t| [t.category_id, t.categorization_source, t.confidence, t.needs_review] }
    assert_equal @cat["dining-out"].id, coffee.reload.category_id
    assert_equal 2, summary.rule
  end

  test "merchant memory wins over keyword rules and counts hits" do
    rule = @user.merchant_rules.create!(merchant_key: "WHOLEFDS MKT", category: @cat["dining-out"])
    t = txn("WHOLEFDS MKT #10234")
    txn("Wholefds Mkt #555", "-3.00")
    summary = run_pipeline
    assert_equal [@cat["dining-out"].id, "memory"], t.reload.then { |x| [x.category_id, x.categorization_source] }
    assert_equal [2, 0], [summary.memory, summary.rule]
    assert_equal 2, rule.reload.hits
    assert_not_nil rule.last_used_at
  end

  test "rows matched by memory or rules never reach the AI; the rest do, with no account data" do
    @user.merchant_rules.create!(merchant_key: "CORNER DELI", category: @cat["dining-out"])
    txn("Corner Deli")
    txn("Netflix.com")
    mystery = txn("ZQX HOLDINGS 4471 LLC", "-25.00")
    ai = FakeAi.new
    run_pipeline(ai:)
    assert_equal 1, ai.calls.size
    assert_equal [{ index: 0, merchant: "ZQX HOLDINGS 4471 LLC", amount: "-25.0", account_purpose: "spending" }],
                 ai.calls.first[:items]
    assert_not_includes ai.calls.first[:allowed_slugs], "transfers"
    assert mystery.reload.needs_review
    assert_nil mystery.category_id
  end

  test "the AI is not called when memory and rules place everything" do
    txn("Netflix.com")
    ai = FakeAi.new
    run_pipeline(ai:)
    assert_empty ai.calls
  end

  test "until AI2, everything memory and rules can't place goes to review" do
    mystery = txn("ZQX HOLDINGS")
    summary = Categorization::Pipeline.call(user: @user, scope: @user.transactions)
    assert mystery.reload.needs_review
    assert_equal 1, summary.needs_review
  end

  test "confident AI answers are used; unsure, unknown or Transfers answers go to review" do
    sure = txn("AAA ONE")
    unsure = txn("BBB TWO")
    transfer = txn("CCC THREE")
    unknown = txn("DDD FOUR")
    ai = FakeAi.new do |items|
      by = items.to_h { |i| [i[:merchant], i[:index]] }
      [{ index: by["AAA ONE"], category_slug: "groceries", confidence: 0.92 },
       { index: by["BBB TWO"], category_slug: "groceries", confidence: 0.4 },
       { index: by["CCC THREE"], category_slug: "transfers", confidence: 0.99 },
       { index: by["DDD FOUR"], category_slug: "made-up", confidence: 0.99 },
       { index: 99, category_slug: "groceries", confidence: 0.99 }]
    end
    summary = run_pipeline(ai:)
    assert_equal [@cat["groceries"].id, "ai", BigDecimal("0.92"), false],
                 sure.reload.then { |t| [t.category_id, t.categorization_source, t.confidence, t.needs_review] }
    [unsure, transfer, unknown].each { |t| assert t.reload.needs_review, t.description }
    assert_equal [1, 3], [summary.ai, summary.needs_review]
  end

  test "sign-aware rules: income only for money in, debt payments only for money out" do
    pay = txn("ACME CORP PAYROLL", "2100.00")
    clawback = txn("ACME CORP PAYROLL", "-50.00", occurrence: 2)
    card_out = txn("CHASE CREDIT CARD PAYMENT", "-300.00")
    card_in = txn("CHASE CREDIT CARD PAYMENT", "300.00")
    refund = txn("TRADER JOE'S", "12.00")
    run_pipeline
    assert_equal @cat["income"].id, pay.reload.category_id
    assert clawback.reload.needs_review
    assert_equal @cat["debt-payments"].id, card_out.reload.category_id
    assert card_in.reload.needs_review
    assert_equal @cat["groceries"].id, refund.reload.category_id, "a refund nets against the same category"
  end

  test "rows the user already categorized are never changed" do
    mine = txn("Netflix.com", category: @cat["groceries"], categorization_source: "user")
    run_pipeline
    assert_equal [@cat["groceries"].id, "user"], mine.reload.then { |t| [t.category_id, t.categorization_source] }
  end

  test "another user's memory and transactions are never used or touched" do
    users(:two).merchant_rules.create!(merchant_key: "ZQX HOLDINGS", category: @cat["groceries"])
    mine = txn("ZQX HOLDINGS")
    theirs = txn("Netflix.com", account: accounts(:two_checking))
    run_pipeline(scope: Transaction.all)
    assert mine.reload.needs_review
    assert_nil mine.category_id
    assert_equal ["none", false], theirs.reload.then { |t| [t.categorization_source, t.needs_review] }
  end

  test "memory pointing at an inactive category is ignored" do
    @user.merchant_rules.create!(merchant_key: "NETFLIX.COM", category: @cat["groceries"])
    @cat["groceries"].update!(active: false)
    t = txn("Netflix.com")
    run_pipeline
    assert_equal [@cat["subscriptions"].id, "rule"], t.reload.then { |x| [x.category_id, x.categorization_source] }
  end

  test "rules never assign a category missing from the active list" do
    @cat["groceries"].update!(active: false)
    t = txn("SAFEWAY #1234")
    run_pipeline
    assert t.reload.needs_review
  end

  test "transfer-like, person-to-person and Amazon rows skip the rules and go to the AI step, with account purpose" do
    side = @user.accounts.create!(name: "Etsy payouts", kind: "p2p", purpose: "side_income")
    txn("TRANSFER TO SAVINGS")
    txn("ZELLE TO J SMITH")
    txn("AMAZON MKTPLACE PMTS")
    txn("VENMO CASHOUT", "120.00", account: side)
    ai = FakeAi.new
    run_pipeline(ai:)
    items = ai.calls.first[:items].to_h { |i| [i[:merchant], i[:account_purpose]] }
    assert_equal({ "TRANSFER TO SAVINGS" => "spending", "ZELLE TO J SMITH" => "spending",
                   "AMAZON MKTPLACE PMTS" => "spending", "VENMO CASHOUT" => "side_income" }, items)
  end
end
