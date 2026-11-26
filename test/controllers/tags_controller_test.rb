require "test_helper"

# S3-L: the caller sees default tags plus their own, and can only change
# their own. The default test token belongs to users(:one).
class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tag = tags(:one)
  end

  test "index returns the default tags and the caller's own, not other users' tags" do
    get api_v1_tags_url, headers: auth_headers, as: :json
    assert_response :success
    ids = response.parsed_body.map { |t| t["id"] }
    assert_equal [tags(:global).id, tags(:one).id].sort, ids.sort
  end

  test "default_tags returns every default tag and ignores user_id" do
    get default_tags_api_v1_tags_url(user_id: users(:two).id), headers: auth_headers, as: :json
    assert_response :success
    assert_equal [tags(:global).id], response.parsed_body.map { |t| t["id"] }
  end

  test "create makes a tag owned by the caller, never a default tag" do
    assert_difference("Tag.count") do
      post api_v1_tags_url, params: { tag: { name: "Mine", user_id: users(:two).id, default_tag: true } }, headers: auth_headers, as: :json
    end
    assert_response :created
    tag = Tag.find(response.parsed_body["id"])
    assert_equal [users(:one).id, false], [tag.user_id, tag.default_tag]
  end

  test "create with an unknown category is 422" do
    assert_no_difference("Tag.count") do
      post api_v1_tags_url, params: { tag: { name: "Mine", category_id: 0 } }, headers: auth_headers, as: :json
    end
    assert_response :unprocessable_entity
  end

  test "show returns the caller's own tag and default tags" do
    get api_v1_tag_url(@tag), headers: auth_headers, as: :json
    assert_response :success
    get api_v1_tag_url(tags(:global)), headers: auth_headers, as: :json
    assert_response :success
  end

  test "update changes the caller's own tag" do
    patch api_v1_tag_url(@tag), params: { tag: { name: "Renamed" } }, headers: auth_headers, as: :json
    assert_response :success
    assert_equal "Renamed", @tag.reload.name
  end

  test "default tags are read-only" do
    patch api_v1_tag_url(tags(:global)), params: { tag: { name: "Changed" } }, headers: auth_headers, as: :json
    assert_response :forbidden
    assert_no_difference("Tag.count") { delete api_v1_tag_url(tags(:global)), headers: auth_headers, as: :json }
    assert_response :forbidden
    assert_equal "Groceries", tags(:global).reload.name
  end

  test "destroy removes the caller's own tag" do
    assert_difference("Tag.count", -1) do
      delete api_v1_tag_url(@tag), headers: auth_headers, as: :json
    end
    assert_response :no_content
  end
end
