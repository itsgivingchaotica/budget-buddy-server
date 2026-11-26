# S4-min (rate limit and AI cost cap): the daily AI cost cap.
#
# Each user may use AI_DAILY_TOKEN_CAP tokens (input + output, all features
# together) per UTC day; the default is 200,000 (about $0.03/day on
# claude-haiku-5-5). AnthropicClient calls `check!` before every request and
# `record!` with the response's usage afterwards, so no Claude call can skip
# the cap.
#
# It's a soft cap: two requests started at the same moment can both pass the
# check, so a user can go over by at most one request's worth.
module AiBudget
  DEFAULT_DAILY_TOKEN_CAP = 200_000

  class Exceeded < StandardError; end

  module_function

  def daily_cap
    Integer(ENV.fetch("AI_DAILY_TOKEN_CAP", DEFAULT_DAILY_TOKEN_CAP))
  end

  def today = Time.now.utc.to_date

  def used_today(user)
    AiUsage.where(user:, day: today).sum("input_tokens + output_tokens")
  end

  def check!(user, feature)
    raise ArgumentError, "unknown AI feature #{feature}" unless AiUsage::FEATURES.include?(feature.to_s)
    raise Exceeded, "daily AI limit reached" if used_today(user) >= daily_cap
  end

  # Atomic add, so concurrent requests never lose counts.
  def record!(user, feature, input_tokens:, output_tokens:)
    now = Time.current
    AiUsage.upsert(
      { user_id: user.id, day: today, feature: feature.to_s, requests: 1,
        input_tokens: input_tokens.to_i, output_tokens: output_tokens.to_i, created_at: now, updated_at: now },
      unique_by: %i[user_id day feature],
      on_duplicate: Arel.sql(<<~SQL.squish)
        requests = ai_usage.requests + 1,
        input_tokens = ai_usage.input_tokens + EXCLUDED.input_tokens,
        output_tokens = ai_usage.output_tokens + EXCLUDED.output_tokens,
        updated_at = EXCLUDED.updated_at
      SQL
    )
  end
end
