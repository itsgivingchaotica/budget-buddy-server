require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @budget = budgets(:one)
  end

  test "should get index" do
    get api_v1_budgets_url, headers: auth_headers, as: :json
    assert_response :success
  end

  test "should create budget" do
    assert_difference("Budget.count") do
      post api_v1_budgets_url, params: { budget: { name: @budget.name, user_id: @budget.user_id } }, headers: auth_headers, as: :json
    end

    assert_response :created
  end

  test "should show budget" do
    get api_v1_budget_url(@budget), headers: auth_headers, as: :json
    assert_response :success
  end

  test "should update budget" do
    patch api_v1_budget_url(@budget), params: { budget: { name: @budget.name, user_id: @budget.user_id } }, headers: auth_headers, as: :json
    assert_response :success
  end

  test "should destroy budget" do
    assert_difference("Budget.count", -1) do
      delete api_v1_budget_url(@budget), headers: auth_headers, as: :json
    end

    assert_response :no_content
  end
end
