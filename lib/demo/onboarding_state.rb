module Demo
  # C5 screenshots: puts one user's onboarding at a chosen step with no
  # answers yet (development only; the demo user by default, another account
  # only when named explicitly by email, as demo:reset). Also removes plan
  # data (as demo:home_state[no_plan]) so Home and Plan show "Make a plan".
  # Imported history stays.
  module OnboardingState
    STEPS = %w[accounts interview merchants plan].freeze

    class Refused < StandardError; end

    module_function

    def call(step:, email: Reset::DEMO_EMAIL, env: Rails.env)
      raise Refused, "demo:onboarding_state runs only in development (this is #{env})" unless env.to_s == "development"
      raise Refused, "unknown step #{step.inspect}; use one of #{STEPS.join(', ')}" unless STEPS.include?(step.to_s)

      user = User.find_by_email_ci(email)
      raise Refused, "no user with that email (run demo:seed, or sign in once in the app)" if user.nil?

      ActiveRecord::Base.transaction do
        HomeState.clear!(user)
        profile = user.financial_profile || user.create_financial_profile!
        profile.update!(answers: { "step" => step.to_s }, answers_version: Onboarding::Interview::VERSION,
                        pay_frequency: nil, next_pay_on: nil, typical_pay_amount: nil, change_appetite: nil)
      end
      { step: step.to_s, user_id: user.id }
    end
  end
end
