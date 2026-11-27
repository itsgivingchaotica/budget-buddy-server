require "test_helper"

# demo:onboarding_state: guards; resets answers to a step and clears plan data.
class Demo::OnboardingStateTest < ActiveSupport::TestCase
  test "refused outside development, for an unknown step or email" do
    assert_raises(Demo::OnboardingState::Refused) { Demo::OnboardingState.call(step: "interview", email: users(:one).email, env: "test") }
    assert_raises(Demo::OnboardingState::Refused) { Demo::OnboardingState.call(step: "party", email: users(:one).email, env: "development") }
    assert_raises(Demo::OnboardingState::Refused) { Demo::OnboardingState.call(step: "interview", email: "nobody@example.invalid", env: "development") }
  end

  test "sets the step with no answers and removes plan data; imports stay" do
    user = users(:one)
    rent = Category.create!(name: "Rent", slug: "rent", kind: "spending", fixed_variable: "fixed", active: true, position: 1)
    user.obligations.create!(name: "Rent", amount: "1", category: rent, first_due_on: Date.new(2026, 12, 1), recurrence: "monthly")
    FinancialProfile.find_or_create_by!(user:).update!(answers: { "step" => "plan", "side_income" => "yes" }, change_appetite: "push")
    Demo::OnboardingState.call(step: "interview", email: user.email, env: "development")
    profile = user.financial_profile.reload
    assert_equal [{ "step" => "interview" }, nil], [profile.answers, profile.change_appetite]
    assert_equal 0, user.obligations.count
    assert transactions(:one_coffee).reload
  end
end
