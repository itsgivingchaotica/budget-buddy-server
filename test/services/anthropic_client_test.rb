require "test_helper"

# AI-0 (Claude connection): the wrapper, with a fake SDK (no API calls).
class AnthropicClientTest < ActiveSupport::TestCase
  Usage = Struct.new(:input_tokens, :output_tokens)
  Block = Struct.new(:type, :text)
  Message = Struct.new(:content, :usage, :stop_reason)

  class FakeSdk
    attr_reader :requests

    def initialize(&respond)
      @respond = respond
      @requests = []
    end

    def messages = self

    def create(**params)
      @requests << params
      @respond.call(params)
    end
  end

  SECRET_PROMPT = "PROMPT-TEXT-SHOULD-NOT-BE-LOGGED".freeze
  SECRET_ANSWER = "ANSWER-TEXT-SHOULD-NOT-BE-LOGGED".freeze

  def reply(json, stop_reason: :end_turn, usage: Usage.new(120, 30))
    ->(_params) { Message.new([Block.new(:text, json)], usage, stop_reason) }
  end

  def call(sdk, log: StringIO.new)
    AnthropicClient.new(sdk:, logger: Logger.new(log)).structured(
      feature: "categorize", use: :categorization, system: "sys", user: SECRET_PROMPT,
      schema: { type: "object" }, max_tokens: 256, for_user: users(:one)
    )
  end

  test "returns parsed JSON with model and token counts" do
    sdk = FakeSdk.new(&reply(%({"results":[],"note":"#{SECRET_ANSWER}"})))
    result = call(sdk)
    assert_equal [], result.data["results"]
    assert_equal ["claude-haiku-5-5", 120, 30], [result.model, result.input_tokens, result.output_tokens]
  end

  test "sends the model from env, structured output and low effort" do
    sdk = FakeSdk.new(&reply("{}"))
    ENV["ANTHROPIC_CATEGORIZATION_MODEL"] = "claude-haiku-5-5"
    call(sdk)
    req = sdk.requests.first
    assert_equal :"claude-haiku-5-5", req[:model]
    assert_equal({ effort: "low", format_: { type: :json_schema, schema: { type: "object" } } }, req[:output_config])
    assert_equal [{ role: "user", content: SECRET_PROMPT }], req[:messages]
  end

  test "model ids default to claude-haiku-5-5 when the env vars are unset" do
    saved = AnthropicClient::MODEL_ENV.values.to_h { |k| [k, ENV.delete(k)] }
    assert_equal "claude-haiku-5-5", AnthropicClient.model_for(:categorization)
    assert_equal "claude-haiku-5-5", AnthropicClient.model_for(:assistant)
  ensure
    saved&.each { |k, v| ENV[k] = v if v }
  end

  test "logs one line with model, tokens and duration, never the key, prompt or answer" do
    log = StringIO.new
    call(FakeSdk.new(&reply(%({"note":"#{SECRET_ANSWER}"}))), log:)
    line = log.string
    assert_match(/\[ai\] feature=categorize model=claude-haiku-5-5 input_tokens=120 output_tokens=30 duration_ms=\d+ outcome=end_turn/, line)
    assert_equal 1, line.lines.size
    assert_no_match(/PROMPT-TEXT|ANSWER-TEXT|sys/, line)
    key = ENV["ANTHROPIC_API_KEY"].to_s
    assert_not_includes line, key if key.present?
  end

  test "API errors log only the class and status, and never the error message" do
    log = StringIO.new
    sdk = FakeSdk.new do |_|
      raise Anthropic::Errors::RateLimitError.new(url: URI("https://api.anthropic.com/v1/messages"), status: 429,
                                                  headers: {}, body: { "echo" => SECRET_PROMPT }, request: nil,
                                                  response: nil, message: "rate limited: #{SECRET_PROMPT}")
    end
    error = assert_raises(AnthropicClient::Unavailable) { call(sdk, log:) }
    assert_includes error.message, "RateLimitError"
    assert_no_match(/PROMPT-TEXT/, error.message)
    assert_match(/outcome=RateLimitError 429/, log.string)
    assert_no_match(/PROMPT-TEXT/, log.string)
  end

  test "refusals, truncation and non-JSON answers raise typed errors" do
    assert_raises(AnthropicClient::Refused) { call(FakeSdk.new(&reply("", stop_reason: :refusal))) }
    assert_raises(AnthropicClient::BadOutput) { call(FakeSdk.new(&reply("{\"a\":", stop_reason: :max_tokens))) }
    assert_raises(AnthropicClient::BadOutput) { call(FakeSdk.new(&reply("not json"))) }
    assert_raises(AnthropicClient::BadOutput) { call(FakeSdk.new(&reply("[1,2]"))) }
  end

  test "the test environment never builds a real client" do
    error = assert_raises(AnthropicClient::NotConfigured) do
      AnthropicClient.new.structured(feature: "categorize", use: :categorization, system: "s", user: "u", schema: {},
                                     for_user: users(:one))
    end
    assert_includes error.message, "test environment"
  end
end
