require "test_helper"

class EntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @entry = entries(:one)
  end

  test "should get index" do
    get api_v1_entries_url, headers: auth_headers, as: :json
    assert_response :success
  end

  test "should create entry" do
    assert_difference("Entry.count") do
      post api_v1_entries_url, params: { entry: { amount: @entry.amount, budget_id: @entry.budget_id, custom_frequency_days: @entry.custom_frequency_days, start_date: @entry.start_date, description: @entry.description, frequency: @entry.frequency } }, headers: auth_headers, as: :json
    end

    assert_response :created
  end

  test "should show entry" do
    get api_v1_entry_url(@entry), headers: auth_headers, as: :json
    assert_response :success
  end

  test "should update entry" do
    patch api_v1_entry_url(@entry), params: { entry: { amount: @entry.amount, budget_id: @entry.budget_id, custom_frequency_days: @entry.custom_frequency_days, start_date: @entry.start_date, description: @entry.description, frequency: @entry.frequency } }, headers: auth_headers, as: :json
    assert_response :success
  end

  test "should destroy entry" do
    assert_difference("Entry.count", -1) do
      delete api_v1_entry_url(@entry), headers: auth_headers, as: :json
    end

    assert_response :no_content
  end
end
