require "test_helper"

# Legacy user endpoints act on the caller's own record only (plan S2).
# The default test token belongs to users(:one).
class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other = users(:two)
  end

  test "index returns only the caller's own record" do
    get api_v1_users_url, headers: auth_headers, as: :json
    assert_response :success
    assert_equal [@user.id], response.parsed_body.map { |u| u["id"] }
  end

  test "show returns the caller's own record" do
    get api_v1_user_url(@user), headers: auth_headers, as: :json
    assert_response :success
  end

  test "show of another user is 404" do
    get api_v1_user_url(@other), headers: auth_headers, as: :json
    assert_response :not_found
  end

  test "show_by_email finds the caller's own email, ignoring case" do
    get show_by_email_api_v1_users_url(email: "ONE@example.com"), headers: auth_headers, as: :json
    assert_response :success
    assert_equal @user.id, response.parsed_body["id"]
  end

  test "show_by_email for someone else's email is 404" do
    get show_by_email_api_v1_users_url(email: @other.email), headers: auth_headers, as: :json
    assert_response :not_found
  end

  test "create provisions the caller instead of trusting the body" do
    assert_no_difference("User.count") do
      post api_v1_users_url, params: { user: { email: "attacker@example.com", first_name: "x", last_name: "y" } }, headers: auth_headers, as: :json
    end
    assert_response :ok
    assert_equal @user.id, response.parsed_body["id"]
  end

  test "create for a new Kinde identity creates that user from Kinde's profile" do
    with_kinde_profile(kinde_profile(sub: "kp_new", email: "kinde@example.com")) do
      assert_difference("User.count", 1) do
        post api_v1_users_url, params: { user: { email: "body@example.com" } }, headers: auth_headers("sub" => "kp_new"), as: :json
      end
    end
    assert_response :created
    assert_equal "kinde@example.com", response.parsed_body["email"]
  end

  test "update changes the caller's names but not the email" do
    patch api_v1_user_url(@user), params: { user: { first_name: "Renamed", email: "changed@example.com" } }, headers: auth_headers, as: :json
    assert_response :success
    assert_equal ["Renamed", "one@example.com"], [@user.reload.first_name, @user.email]
  end

  test "update of another user is 404 and changes nothing" do
    patch api_v1_user_url(@other), params: { user: { first_name: "Hacked" } }, headers: auth_headers, as: :json
    assert_response :not_found
    assert_not_equal "Hacked", @other.reload.first_name
  end

  test "destroy of another user is 404" do
    assert_no_difference("User.count") do
      delete api_v1_user_url(@other), headers: auth_headers, as: :json
    end
    assert_response :not_found
  end

  test "destroy removes the caller's own record" do
    # Users with transactions can't be deleted yet (accounts keep their
    # history); that waits for a delete-account design. See PROGRESS.md.
    transactions(:one_coffee).destroy!
    imports(:one_nov).destroy!
    assert_difference("User.count", -1) do
      delete api_v1_user_url(@user), headers: auth_headers, as: :json
    end
    assert_response :no_content
  end

  test "destroy is 409 and deletes nothing when the user has transactions (known debt)" do
    tables = [User, Budget, Account, FinancialProfile, Import, Transaction]
    before = tables.map(&:count)
    delete api_v1_user_url(@user), headers: auth_headers, as: :json
    assert_response :conflict
    assert_equal "user_has_data", response.parsed_body["error"]
    assert_includes response.parsed_body["message"], "can't be deleted yet"
    assert_equal before, tables.map(&:count)
  end

  test "a valid token without a provisioned user gets 403 on user endpoints" do
    get api_v1_users_url, headers: auth_headers("sub" => "kp_not_provisioned"), as: :json
    assert_response :forbidden
    assert_equal({ "error" => "user_not_provisioned" }, response.parsed_body)
  end
end
