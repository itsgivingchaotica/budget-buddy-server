require "test_helper"

class EntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @entry = entries(:one)
  end

  test "should get index" do
    get entries_url, as: :json
    assert_response :success
  end

  test "should create entry" do
    assert_difference("Entry.count") do
      post entries_url, params: { entry: { amount: @entry.amount, budget_id: @entry.budget_id, custom_frequency_days: @entry.custom_frequency_days, date: @entry.date, description: @entry.description, entry_type: @entry.entry_type, frequency: @entry.frequency } }, as: :json
    end

    assert_response :created
  end

  test "should show entry" do
    get entry_url(@entry), as: :json
    assert_response :success
  end

  test "should update entry" do
    patch entry_url(@entry), params: { entry: { amount: @entry.amount, budget_id: @entry.budget_id, custom_frequency_days: @entry.custom_frequency_days, date: @entry.date, description: @entry.description, entry_type: @entry.entry_type, frequency: @entry.frequency } }, as: :json
    assert_response :success
  end

  test "should destroy entry" do
    assert_difference("Entry.count", -1) do
      delete entry_url(@entry), as: :json
    end

    assert_response :no_content
  end
end
