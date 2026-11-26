require "test_helper"

# DM-1: the seeded flat list (plan §2.5, SPEC_LEFT_TO_SPEND.md §7).
class CategorySeedTest < ActionDispatch::IntegrationTest
  FLEXIBLE = %w[groceries dining-out entertainment transportation healthcare clothing
                personal-care gifts travel home-improvement other].freeze
  FIXED = %w[rent utilities subscriptions insurance debt-payments education].freeze

  setup do
    Rails.application.load_seed
  end

  def counts
    [Category.count, Category.active_list.count, Tag.count, Category.maximum(:updated_at)]
  end

  test "seeding twice changes nothing" do
    before = counts
    Rails.application.load_seed
    assert_equal before, counts
  end

  test "17 spending categories with the spec's fixed/variable labels, plus Income and Transfers" do
    assert_equal (FLEXIBLE + FIXED).sort, Category.spending.where(active: true).pluck(:slug).sort
    assert_equal FLEXIBLE.sort, Category.flexible.pluck(:slug).sort
    assert_equal FIXED.sort, Category.spending.where(fixed_variable: "fixed").pluck(:slug).sort
    assert_equal ["income"], Category.where(kind: "income").pluck(:slug)
    assert_equal ["transfers"], Category.where(kind: "transfer").pluck(:slug)
    assert_equal "Debt Payments", Category.find_by(slug: "debt-payments").name
  end

  test "the agreed need/want and recurrence defaults" do
    labels = Category.active_list.pluck(:slug, :need_want, :recurrence_label).to_h { |s, n, r| [s, [n, r]] }
    assert_equal ["need", "recurring"], labels["rent"]
    assert_equal ["want", "recurring"], labels["subscriptions"]
    assert_equal ["want", nil], labels["dining-out"]
    assert_equal [nil, nil], labels["other"]
    assert_equal %w[debt-payments insurance rent subscriptions utilities],
                 labels.select { |_, (_, r)| r == "recurring" }.keys.sort
  end

  test "new categories leave category_type NULL, so categories#default returns only legacy rows" do
    assert Category.active_list.all? { |c| c.category_type.nil? }

    get default_api_v1_categories_url, headers: auth_headers, as: :json
    assert_response :success
    assert response.parsed_body.all? { |c| c["kind"] == "legacy" }
    assert_equal Category.where(category_type: "default").count, response.parsed_body.size
  end

  test "legacy categories are inactive with legacy slugs, and gained no tags" do
    legacy = Category.where(category_type: "default")
    assert legacy.all? { |c| c.legacy? && !c.active && c.slug.start_with?("legacy-") }
    assert_equal 0, Tag.where(category_id: Category.active_list.select(:id)).count
  end

  test "GET /categories returns the active list in order with labels" do
    get api_v1_categories_url, headers: auth_headers, as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal Category.active_list.pluck(:slug), body.map { |c| c["slug"] }
    assert_equal "groceries", body.first["slug"]
    assert_equal "variable", body.first["fixed_variable"]
    assert_not body.any? { |c| c["kind"] == "legacy" }
  end
end
