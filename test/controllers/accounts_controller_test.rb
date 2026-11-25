require "test_helper"

# DM-2 (accounts) API. The default test token belongs to users(:one).
class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one_checking)
  end

  test "index lists the caller's active accounts without owner ids" do
    get api_v1_accounts_url, headers: auth_headers, as: :json
    assert_response :success
    assert_equal [@account.id], response.parsed_body.map { |a| a["id"] }
    assert_not response.parsed_body.first.key?("user_id")
  end

  test "create adds an account for the caller, ignoring an injected user_id" do
    assert_difference("users(:one).accounts.count", 1) do
      post api_v1_accounts_url, params: { account: { name: "Venmo", kind: "p2p", purpose: "spending", user_id: users(:two).id } },
                                headers: auth_headers, as: :json
    end
    assert_response :created
    assert_equal "Venmo", response.parsed_body["name"]
  end

  test "create requires name, kind and purpose" do
    post api_v1_accounts_url, params: { account: { name: "" } }, headers: auth_headers, as: :json
    assert_response :unprocessable_entity
    assert_equal %w[kind name purpose], response.parsed_body["errors"].keys.sort
  end

  test "create rejects a duplicate name ignoring case" do
    post api_v1_accounts_url, params: { account: { name: "EVERYDAY checking", kind: "savings", purpose: "savings" } },
                              headers: auth_headers, as: :json
    assert_response :unprocessable_entity
  end

  test "update changes name, kind, purpose and note" do
    patch api_v1_account_url(@account), params: { account: { name: "Main", purpose: "bills", purpose_note: "rent comes out of here" } },
                                        headers: auth_headers, as: :json
    assert_response :success
    assert_equal ["Main", "bills", "rent comes out of here"], [@account.reload.name, @account.purpose, @account.purpose_note]
  end

  test "destroy archives instead of deleting, and hides the account from the list" do
    assert_no_difference("Account.count") do
      delete api_v1_account_url(@account), headers: auth_headers, as: :json
    end
    assert_response :no_content
    assert @account.reload.archived?

    get api_v1_accounts_url, headers: auth_headers, as: :json
    assert_empty response.parsed_body
    get api_v1_accounts_url(include_archived: true), headers: auth_headers, as: :json
    assert_equal [@account.id], response.parsed_body.map { |a| a["id"] }
  end

  test "an archived account is still readable but can't be changed" do
    @account.archive!
    get api_v1_account_url(@account), headers: auth_headers, as: :json
    assert_response :success

    patch api_v1_account_url(@account), params: { account: { name: "Back" } }, headers: auth_headers, as: :json
    assert_response :unprocessable_entity
    assert_equal({ "error" => "archived" }, response.parsed_body)
  end
end
