require "test_helper"

# S4-min (rate limit and AI cost cap): the daily token cap and usage rows.
class AiBudgetTest < ActiveSupport::TestCase
  Usage = Struct.new(:input_tokens, :output_tokens)
  Block = Struct.new(:type, :text)
  Message = Struct.new(:content, :usage, :stop_reason)

  class FakeSdk
    attr_reader :calls

    def initialize(stop_reason: :end_turn) = (@calls = 0) && (@stop_reason = stop_reason)
    def messages = self

    def create(**)
      @calls += 1
      Message.new([Block.new(:text, "{}")], Usage.new(1_000, 200), @stop_reason)
    end
  end

  setup { @user = users(:one) }

  def ask(sdk, user: @user)
    AnthropicClient.new(sdk:, logger: Logger.new(nil)).structured(
      feature: "categorize", use: :categorization, system: "s", user: "u", schema: {}, for_user: user
    )
  end

  test "usage rows add up per user, day and feature" do
    AiBudget.record!(@user, :categorize, input_tokens: 100, output_tokens: 20)
    AiBudget.record!(@user, :categorize, input_tokens: 50, output_tokens: 5)
    AiBudget.record!(@user, :assistant, input_tokens: 10, output_tokens: 1)
    row = AiUsage.find_by!(user: @user, day: AiBudget.today, feature: "categorize")
    assert_equal [2, 150, 25], [row.requests, row.input_tokens, row.output_tokens]
    assert_equal 186, AiBudget.used_today(@user)
    assert_equal 0, AiBudget.used_today(users(:two))
  end

  test "every Claude call is checked first and its usage recorded" do
    sdk = FakeSdk.new
    2.times { ask(sdk) }
    row = AiUsage.find_by!(user: @user, feature: "categorize")
    assert_equal [2, 2_000, 400], [row.requests, row.input_tokens, row.output_tokens]
  end

  test "over the cap: Exceeded is raised and the client sends NO request" do
    ENV["AI_DAILY_TOKEN_CAP"] = "1000"
    AiBudget.record!(@user, :assistant, input_tokens: 900, output_tokens: 100)
    sdk = FakeSdk.new
    assert_raises(AiBudget::Exceeded) { ask(sdk) }
    assert_equal 0, sdk.calls
    ask(sdk, user: users(:two)) # the cap is per user: this must not raise
    assert_equal 1, sdk.calls
  ensure
    ENV.delete("AI_DAILY_TOKEN_CAP")
  end

  test "yesterday's usage doesn't count today" do
    ENV["AI_DAILY_TOKEN_CAP"] = "1000"
    AiUsage.create!(user: @user, day: AiBudget.today - 1, feature: "categorize", requests: 1, input_tokens: 5_000)
    assert_nothing_raised { AiBudget.check!(@user, :categorize) }
  ensure
    ENV.delete("AI_DAILY_TOKEN_CAP")
  end

  test "a refused answer still counts toward the cap" do
    assert_raises(AnthropicClient::Refused) { ask(FakeSdk.new(stop_reason: :refusal)) }
    assert_equal 1_200, AiBudget.used_today(@user)
  end

  test "a metered call must name the user; unknown features are rejected" do
    assert_raises(ArgumentError) do
      AnthropicClient.new(sdk: FakeSdk.new).structured(feature: "categorize", use: :categorization, system: "s", user: "u", schema: {})
    end
    assert_raises(ArgumentError) { AiBudget.check!(@user, :poetry) }
  end

  test "database rejects unknown features and negative counts" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      AiUsage.transaction(requires_new: true) { AiUsage.insert_all!([{ user_id: @user.id, day: AiBudget.today, feature: "poetry", created_at: Time.current, updated_at: Time.current }]) }
    end
    assert_kind_of PG::CheckViolation, error.cause
  end
end
