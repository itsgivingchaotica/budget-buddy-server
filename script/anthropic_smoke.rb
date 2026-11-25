# AI-0 (Claude connection): one real structured-output call, to confirm the
# key, the model id and the SDK work. NOT part of the test suite; it costs a
# fraction of a cent. Run:  bin/rails runner script/anthropic_smoke.rb
#
# It prints only the model, token counts, duration and whether the answer
# matched the schema: never the key, the prompt or the answer.
schema = {
  type: "object",
  additionalProperties: false,
  required: ["results"],
  properties: {
    results: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: %w[index category_slug confidence],
        properties: {
          index: { type: "integer" },
          category_slug: { type: "string", enum: %w[groceries dining-out transportation other] },
          confidence: { type: "number" }
        }
      }
    }
  }
}

result = AnthropicClient.new(logger: Logger.new($stdout)).structured(
  feature: "smoke",
  use: :categorization,
  unmetered: true, # offline check only; real features are always metered (S4-min)
  system: "You categorize bank transactions. Reply only with the JSON the schema asks for.",
  user: "Categorize each item: [{\"index\":0,\"merchant\":\"MAPLE STREET GROCER\",\"amount\":\"-23.10\"}," \
        "{\"index\":1,\"merchant\":\"CITY PARKING\",\"amount\":\"-6.00\"}]",
  schema:,
  max_tokens: 512
)

valid = result.data["results"].is_a?(Array) && result.data["results"].size == 2 &&
        result.data["results"].all? { |r| r["index"].is_a?(Integer) && r["confidence"].is_a?(Numeric) }
puts "model=#{result.model} input_tokens=#{result.input_tokens} output_tokens=#{result.output_tokens} " \
     "duration_ms=#{result.duration_ms} schema_valid=#{valid}"
