require "json"

# AI-0 (Claude connection): the one place the app talks to Claude.
#
# - The API key comes from ANTHROPIC_API_KEY and is only handed to the SDK.
# - Model ids come from env (AD6): ANTHROPIC_CATEGORIZATION_MODEL and
#   ANTHROPIC_ASSISTANT_MODEL, both defaulting to claude-haiku-5-5.
# - Every call logs ONE line: feature, model, token counts, duration and
#   outcome. Never the key, the prompt, the response text, or an error's
#   message (which can echo request content) - only the error class and
#   HTTP status.
# - Tests swap the SDK for a fake (`sdk:`), so the suite never calls the API.
#
# S4-min (rate limit and AI cost cap) wraps this: AiBudget.check! must run
# before every call.
class AnthropicClient
  DEFAULT_MODEL = "claude-haiku-5-5".freeze
  MODEL_ENV = {
    categorization: "ANTHROPIC_CATEGORIZATION_MODEL",
    assistant: "ANTHROPIC_ASSISTANT_MODEL"
  }.freeze
  TIMEOUT_SECONDS = 30
  MAX_RETRIES = 2

  class Error < StandardError; end
  class NotConfigured < Error; end
  # Claude declined (stop_reason refusal); callers send the rows to review.
  class Refused < Error; end
  # The answer was cut off or isn't the JSON the schema asked for.
  class BadOutput < Error; end
  # The API failed (network, 4xx, 5xx) after the SDK's retries.
  class Unavailable < Error; end

  Result = Data.define(:data, :model, :input_tokens, :output_tokens, :duration_ms)

  def self.model_for(use)
    ENV[MODEL_ENV.fetch(use)].presence || DEFAULT_MODEL
  end

  def initialize(sdk: nil, logger: Rails.logger)
    @sdk = sdk
    @logger = logger
  end

  # One structured-output request. `schema` is a JSON Schema for the whole
  # answer; returns a Result whose `data` is the parsed JSON (a Hash).
  def structured(feature:, use:, system:, user:, schema:, max_tokens: 2_048, effort: "low")
    model = self.class.model_for(use)
    started = monotonic
    message = sdk.messages.create(
      model: model.to_sym,
      max_tokens:,
      system_: system,
      messages: [{ role: "user", content: user }],
      output_config: { effort:, format_: { type: :json_schema, schema: } }
    )
    duration_ms = ((monotonic - started) * 1000).round
    usage = message.usage
    log(feature:, model:, input: usage&.input_tokens, output: usage&.output_tokens, duration_ms:,
        outcome: message.stop_reason)

    raise Refused, "Claude declined the request" if message.stop_reason == :refusal
    raise BadOutput, "the answer was cut off (max_tokens)" if message.stop_reason == :max_tokens

    text = message.content.select { |block| block.type == :text }.map(&:text).join
    data = JSON.parse(text)
    raise BadOutput, "the answer isn't a JSON object" unless data.is_a?(Hash)

    Result.new(data:, model:, input_tokens: usage.input_tokens, output_tokens: usage.output_tokens, duration_ms:)
  rescue JSON::ParserError
    raise BadOutput, "the answer isn't valid JSON"
  rescue Anthropic::Errors::APIStatusError => e
    log(feature:, model:, duration_ms: elapsed_ms(started), outcome: "#{e.class.name.demodulize} #{e.status}")
    raise Unavailable, "Claude API error (#{e.class.name.demodulize}, HTTP #{e.status})"
  rescue Anthropic::Errors::APIConnectionError => e
    log(feature:, model:, duration_ms: elapsed_ms(started), outcome: e.class.name.demodulize)
    raise Unavailable, "Claude API unreachable (#{e.class.name.demodulize})"
  end

  private

  def sdk
    @sdk ||= begin
      # dotenv loads .env in tests too; a test must pass a fake `sdk:`.
      raise NotConfigured, "real Claude calls are disabled in the test environment" if Rails.env.test?

      key = ENV["ANTHROPIC_API_KEY"].presence
      raise NotConfigured, "ANTHROPIC_API_KEY is not set" if key.nil?

      Anthropic::Client.new(api_key: key, max_retries: MAX_RETRIES, timeout: TIMEOUT_SECONDS)
    end
  end

  def log(feature:, model:, duration_ms:, outcome:, input: nil, output: nil)
    @logger.info("[ai] feature=#{feature} model=#{model} input_tokens=#{input || '-'} " \
                 "output_tokens=#{output || '-'} duration_ms=#{duration_ms || '-'} outcome=#{outcome}")
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def elapsed_ms(started)
    started && ((monotonic - started) * 1000).round
  end
end
