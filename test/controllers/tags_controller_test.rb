require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tag = tags(:one)
  end

  test "should get index" do
    get api_v1_tags_url, headers: auth_headers, as: :json
    assert_response :success
  end

  test "should create tag" do
    assert_difference("Tag.count") do
      post api_v1_tags_url, params: { tag: { name: @tag.name } }, headers: auth_headers, as: :json
    end

    assert_response :created
  end

  test "should show tag" do
    get api_v1_tag_url(@tag), headers: auth_headers, as: :json
    assert_response :success
  end

  test "should update tag" do
    patch api_v1_tag_url(@tag), params: { tag: { name: @tag.name } }, headers: auth_headers, as: :json
    assert_response :success
  end

  test "should destroy tag" do
    assert_difference("Tag.count", -1) do
      delete api_v1_tag_url(@tag), headers: auth_headers, as: :json
    end

    assert_response :no_content
  end
end
