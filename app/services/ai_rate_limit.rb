# S4-min (rate limit and AI cost cap): per-user request limits on AI
# endpoints, e.g. 20 categorize requests per hour.
#
# Applied in the controller, after the login token is verified, so the user
# is real. (A per-user limit in Rack::Attack would run before
# authentication and trust an unverified user id, letting anyone use up
# someone else's limit.)
#
# Fixed windows (one hour for categorize; one day for plan drafts, PL1 and
# SPEC_ONBOARDING_PLAN §6.3) in an in-process memory store: fine for one
# server; several servers would need a shared store (Redis or similar).
module AiRateLimit
  LIMITS = { categorize: 20, plan: 5 }.freeze # requests per window
  WINDOWS = { categorize: 1.hour, plan: 1.day }.freeze
  WINDOW = 1.hour # the default window

  class Limited < StandardError
    attr_reader :retry_after

    def initialize(retry_after)
      @retry_after = retry_after
      super("too many requests")
    end
  end

  module_function

  def store
    @store ||= ActiveSupport::Cache::MemoryStore.new
  end

  def reset! = store.clear

  def hit!(user, feature, now: Time.now)
    limit = LIMITS.fetch(feature)
    length = WINDOWS.fetch(feature, WINDOW).to_i
    window = now.to_i / length
    count = store.increment("ai:#{user.id}:#{feature}:#{window}", 1, expires_in: length * 2)
    return count if count <= limit

    raise Limited, ((window + 1) * length) - now.to_i
  end
end
