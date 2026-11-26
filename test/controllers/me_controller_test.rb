# frozen_string_literal: true

require "test_helper"

class MeControllerTest < ActionDispatch::IntegrationTest
  NEW_SUB = "kp_first_login"

  test "requires a token" do
    get api_v1_me_url, as: :json
    assert_response :unauthorized
  end

  test "returns the already-linked user without calling Kinde" do
    fake = with_kinde_profile(nil) do
      get api_v1_me_url, headers: auth_headers, as: :json
    end

    assert_response :success
    body = response.parsed_body
    assert_equal users(:one).id, body["id"]
    assert_equal false, body["onboarding_completed"]
    assert_equal({ "week_starts_on" => 1, "time_zone" => nil }, body["profile"])
    assert_not body.key?("kinde_id")
    assert_equal 0, fake.calls
  end

  test "first call creates the user and profile; repeat calls create nothing" do
    with_kinde_profile(kinde_profile(sub: NEW_SUB, email: "first@example.com")) do |fake|
      assert_difference(["User.count", "FinancialProfile.count"], 1) do
        get api_v1_me_url, headers: auth_headers("sub" => NEW_SUB), as: :json
      end
      assert_response :success
      assert_equal "first@example.com", response.parsed_body["email"]

      assert_no_difference(["User.count", "FinancialProfile.count"]) do
        2.times { get api_v1_me_url, headers: auth_headers("sub" => NEW_SUB), as: :json }
      end
      assert_equal 1, fake.calls, "Kinde is only asked on the first call"
    end
  end

  test "the server sends Kinde the caller's own verified token" do
    headers = auth_headers("sub" => NEW_SUB)
    fake = with_kinde_profile(kinde_profile(sub: NEW_SUB, email: "first@example.com")) do
      get api_v1_me_url, headers: headers, as: :json
    end
    assert_equal [headers["Authorization"].delete_prefix("Bearer ")], fake.tokens
  end

  test "an email in the request is ignored; the Kinde email is used" do
    with_kinde_profile(kinde_profile(sub: NEW_SUB, email: "real@example.com")) do
      get api_v1_me_url, params: { email: users(:two).email, user: { email: users(:two).email } },
                         headers: auth_headers("sub" => NEW_SUB)
    end

    assert_response :success
    assert_equal "real@example.com", response.parsed_body["email"]
    assert_equal "kp_other_user", users(:two).reload.kinde_id
  end

  test "stores a valid device time zone once, and never overwrites it" do
    get api_v1_me_url, params: { time_zone: "Europe/London" }, headers: auth_headers
    assert_equal "Europe/London", response.parsed_body.dig("profile", "time_zone")

    get api_v1_me_url, params: { time_zone: "America/New_York" }, headers: auth_headers
    assert_equal "Europe/London", users(:one).reload.financial_profile.time_zone
  end

  test "ignores an invalid time zone" do
    get api_v1_me_url, params: { time_zone: "Mars/Olympus_Mons" }, headers: auth_headers
    assert_response :success
    assert_nil users(:one).reload.financial_profile.time_zone
  end

  test "an email match that can't be linked returns 409 and changes nothing" do
    with_kinde_profile(kinde_profile(sub: NEW_SUB, email: users(:two).email, email_verified: true)) do
      assert_no_difference("User.count") do
        get api_v1_me_url, headers: auth_headers("sub" => NEW_SUB), as: :json
      end
    end

    assert_response :conflict
    assert_equal({ "error" => "account_link_required" }, response.parsed_body)
    assert_equal "kp_other_user", users(:two).reload.kinde_id
  end

  test "Kinde's profile being unavailable returns 503" do
    with_kinde_profile(Kinde::UserProfileFetcher::Unavailable.new("down")) do
      get api_v1_me_url, headers: auth_headers("sub" => NEW_SUB), as: :json
    end

    assert_response :service_unavailable
    assert_equal({ "error" => "profile_unavailable" }, response.parsed_body)
  end
end
