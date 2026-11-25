require "test_helper"
require "minitest/mock"

# S4-min (rate limit and AI cost cap): the per-user limit on
# POST /transactions/categorize, the daily cap, and the per-IP throttle.
class AiLimitsTest < ActionDispatch::IntegrationTest
  Usage = Struct.new(:input_tokens, :output_tokens)
  Block = Struct.new(:type, :text)
  Message = Struct.new(:content, :usage, :stop_reason)

  # An AI step that really goes through AnthropicClient (so the cap applies),
  # with a fake SDK that counts requests.
  class CountingSdk
    attr_reader :calls

    def initialize = @calls = 0
    def messages = self

    def create(**)
      @calls += 1
      Message.new([Block.new(:text, '{"results":[]}')], Usage.new(500, 50), :end_turn)
    end
  end

  class ClaudeStep
    def initialize(user, sdk) = (@user = user) && (@client = AnthropicClient.new(sdk:, logger: Logger.new(nil)))

    def categorize(items:, allowed_slugs:)
      @client.structured(feature: "categorize", use: :categorization, system: "s", user: items.to_json,
                         schema: { type: "object" }, for_user: @user).data["results"]
    end
  end

  setup do
    AiRateLimit.reset!
    @mine = accounts(:one_checking).transactions.create!(posted_on: Date.new(2026, 11, 2), amount: "-9.00",
                                                         description: "ZQX HOLDINGS", needs_review: true)
  end

  def categorize!(headers: auth_headers)
    post categorize_api_v1_transactions_url, headers:, as: :json
  end

  test "categorize re-runs the pipeline on rows waiting for review" do
    categorize!
    assert_response :success
    assert_equal({ "memory" => 0, "rule" => 0, "ai" => 0, "needs_review" => 1 }, response.parsed_body["categorized"])
  end

  test "20 categorize requests per hour per user, then 429 JSON with Retry-After" do
    20.times { categorize! }
    assert_response :success
    categorize!
    assert_response :too_many_requests
    assert_equal "rate_limited", response.parsed_body["error"]
    assert_operator response.headers["Retry-After"].to_i, :>, 0

    categorize!(headers: auth_headers("sub" => users(:two).kinde_id))
    assert_response :success, "the limit is per user"
  end

  test "over the daily cap: 429 and the AI client gets no call" do
    ENV["AI_DAILY_TOKEN_CAP"] = "100"
    AiBudget.record!(users(:one), :categorize, input_tokens: 100, output_tokens: 0)
    sdk = CountingSdk.new
    Categorization::Pipeline.stub(:ai_for, ->(user) { ClaudeStep.new(user, sdk) }) do
      categorize!
    end
    assert_response :too_many_requests
    assert_equal "ai_daily_cap_reached", response.parsed_body["error"]
    assert_equal 0, sdk.calls
    assert @mine.reload.needs_review
  ensure
    ENV.delete("AI_DAILY_TOKEN_CAP")
  end

  test "under the cap the AI step runs once and its usage is recorded" do
    sdk = CountingSdk.new
    Categorization::Pipeline.stub(:ai_for, ->(user) { ClaudeStep.new(user, sdk) }) do
      categorize!
    end
    assert_response :success
    assert_equal 1, sdk.calls
    assert_equal 550, AiBudget.used_today(users(:one))
  end

  test "if the cap is hit during an import, rows go to review and the import still succeeds" do
    Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 1)
    ENV["AI_DAILY_TOKEN_CAP"] = "1"
    AiBudget.record!(users(:one), :categorize, input_tokens: 5, output_tokens: 0)
    sdk = CountingSdk.new
    upload = Rack::Test::UploadedFile.new(StringIO.new("date,description,amount\n2026-12-01,SAFEWAY #9,-20.00\n2026-12-02,ZQX THING,-3.00\n"),
                                          "text/csv", original_filename: "dec.csv")
    Categorization::Pipeline.stub(:ai_for, ->(user) { ClaudeStep.new(user, sdk) }) do
      post api_v1_account_imports_url(accounts(:one_checking)), params: { file: upload }, headers: auth_headers
    end
    assert_response :created
    assert_equal({ "memory" => 0, "rule" => 1, "ai" => 0, "needs_review" => 1 }, response.parsed_body["categorized"])
    assert_equal 0, sdk.calls
  ensure
    ENV.delete("AI_DAILY_TOKEN_CAP")
  end

  test "per-IP throttle on the API returns 429 JSON" do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
    API_REQUESTS_PER_IP.times { get api_v1_categories_url, as: :json }
    assert_response :unauthorized
    get api_v1_categories_url, as: :json
    assert_response :too_many_requests
    assert_equal "rate_limited", response.parsed_body["error"]
    assert response.headers["Retry-After"].present?
    get "/up"
    assert_response :success, "only /api/ paths are throttled"
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.cache.store.clear
  end
end
