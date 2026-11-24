# frozen_string_literal: true

require "test_helper"

module Users
  # S2 / SR-1: account linking and user creation from a Kinde identity.
  class KindeProvisionerTest < ActiveSupport::TestCase
    NEW_SUB = "kp_brand_new"

    setup do
      @log = StringIO.new
      @logger = ActiveSupport::Logger.new(@log)
      @legacy = User.create!(first_name: "Legacy", last_name: "User", email: "Legacy.User@Example.com")
    end

    def provision(profile, sub: NEW_SUB, token: "test-token")
      fetcher = AuthTestHelper::FakeProfileFetcher.new(profile)
      result = KindeProvisioner.new(profile_fetcher: fetcher, logger: @logger).call(sub: sub, access_token: token)
      [result, fetcher]
    end

    # --- existing identity ------------------------------------------------------

    test "returns the user already linked to the sub without calling Kinde" do
      result, fetcher = provision(nil, sub: users(:one).kinde_id)

      assert_equal :existing, result.status
      assert_equal users(:one), result.user
      assert_equal 0, fetcher.calls
    end

    # --- SR-1 linking -------------------------------------------------------------

    test "links an unlinked user when Kinde says the email is verified (case-insensitive match)" do
      result, fetcher = provision(kinde_profile(sub: NEW_SUB, email: "legacy.user@example.com", email_verified: true))

      assert_equal :linked, result.status
      assert_equal @legacy.id, result.user.id
      assert_equal NEW_SUB, @legacy.reload.kinde_id
      assert_equal ["test-token"], fetcher.tokens
      assert_includes @log.string, "linked user_id=#{@legacy.id} to sub=#{NEW_SUB}"
      assert_not_includes @log.string, "legacy.user@example.com"
      assert_not_includes @log.string, "test-token"
    end

    test "does not link when the email is not verified" do
      assert_raises(KindeProvisioner::Conflict) do
        provision(kinde_profile(sub: NEW_SUB, email: @legacy.email, email_verified: false))
      end
      assert_nil @legacy.reload.kinde_id
      assert_includes @log.string, "reason=email_not_verified"
    end

    test "does not link when Kinde doesn't report email_verified at all" do
      assert_raises(KindeProvisioner::Conflict) do
        provision(kinde_profile(sub: NEW_SUB, email: @legacy.email, email_verified: nil))
      end
      assert_nil @legacy.reload.kinde_id
    end

    test "does not link when email_verified is truthy but not true" do
      assert_raises(KindeProvisioner::Conflict) do
        provision(kinde_profile(sub: NEW_SUB, email: @legacy.email, email_verified: "true"))
      end
      assert_nil @legacy.reload.kinde_id
    end

    test "never overwrites an existing kinde_id" do
      other = users(:two)
      assert_raises(KindeProvisioner::Conflict) do
        provision(kinde_profile(sub: NEW_SUB, email: other.email.upcase, email_verified: true))
      end
      assert_equal "kp_other_user", other.reload.kinde_id
      assert_includes @log.string, "reason=already_linked"
    end

    test "a refused link creates no user and no profile" do
      assert_no_difference(["User.count", "FinancialProfile.count"]) do
        assert_raises(KindeProvisioner::Conflict) do
          provision(kinde_profile(sub: NEW_SUB, email: @legacy.email, email_verified: false))
        end
      end
    end

    # --- creation -------------------------------------------------------------------

    test "creates a new user with a profile when no account has the email" do
      result = nil
      assert_difference(["User.count", "FinancialProfile.count"], 1) do
        result, = provision(kinde_profile(sub: NEW_SUB, email: "fresh@example.com"))
      end

      assert_equal :created, result.status
      user = result.user
      assert_equal [NEW_SUB, "fresh@example.com", "New", "Person"], [user.kinde_id, user.email, user.first_name, user.last_name]
      assert_equal 1, user.financial_profile.week_starts_on
      assert_nil user.financial_profile.time_zone
      assert_not user.financial_profile.onboarding_completed?
    end

    test "creates a user even when Kinde provides no email or names" do
      result, = provision({ "id" => NEW_SUB })

      assert_equal :created, result.status
      assert_nil result.user.email
      assert result.user.financial_profile
    end

    test "repeated calls create exactly one user and one profile" do
      provision(kinde_profile(sub: NEW_SUB, email: "fresh@example.com"))

      assert_no_difference(["User.count", "FinancialProfile.count"]) do
        result, fetcher = provision(kinde_profile(sub: NEW_SUB, email: "fresh@example.com"))
        assert_equal :existing, result.status
        assert_equal 0, fetcher.calls
      end
    end

    test "adds a missing profile to an existing linked user exactly once" do
      user = users(:one)
      assert_nil user.financial_profile

      assert_difference("FinancialProfile.count", 1) { provision(nil, sub: user.kinde_id) }
      assert_no_difference("FinancialProfile.count") { provision(nil, sub: user.kinde_id) }
    end

    # --- Kinde problems -------------------------------------------------------------

    test "rejects a profile for a different subject" do
      assert_no_difference("User.count") do
        assert_raises(Kinde::UserProfileFetcher::Unavailable) do
          provision(kinde_profile(sub: "kp_someone_else", email: "fresh@example.com"))
        end
      end
    end

    test "propagates Kinde being unavailable without creating anything" do
      assert_no_difference("User.count") do
        assert_raises(Kinde::UserProfileFetcher::Unavailable) { provision(nil) }
      end
    end
  end
end
