# S4-min (rate limit and AI cost cap): a general per-IP limit on the API.
# Per-user AI limits live in AiRateLimit (after authentication), and the
# daily token cap in AiBudget.
#
# In-process memory store: fine for one server. Disabled in tests by
# default (the suite sends hundreds of requests from one IP); the
# rate-limit tests turn it on.
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
Rack::Attack.enabled = !Rails.env.test?

API_REQUESTS_PER_IP = Integer(ENV.fetch("API_REQUESTS_PER_IP_PER_5MIN", 300))

Rack::Attack.throttle("api/ip", limit: API_REQUESTS_PER_IP, period: 5.minutes) do |request|
  request.ip if request.path.start_with?("/api/")
end

Rack::Attack.throttled_responder = lambda do |request|
  match = request.env["rack.attack.match_data"] || {}
  retry_after = match[:period] ? (match[:period] - (match[:epoch_time].to_i % match[:period])) : 60
  [429, { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
   [{ error: "rate_limited", retry_after: }.to_json]]
end
