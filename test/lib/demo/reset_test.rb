require "test_helper"

# DEMO-G: demo:reset only runs in development and only touches the demo user.
class Demo::ResetTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed
    @demo = User.create!(email: Demo::Reset::DEMO_EMAIL, first_name: "Demo", last_name: "User")
    Demo::Seeder.call(user: @demo)
    @demo.merchant_rules.create!(merchant_key: "ZQX", category: Category.active_list.first)
  end

  test "refuses to run outside development" do
    %w[test production staging].each do |env|
      assert_no_difference -> { Transaction.count } do
        assert_raises(Demo::Reset::Refused) { Demo::Reset.call(env:) }
      end
    end
    # The default is the current environment (test), so this refuses too.
    assert_raises(Demo::Reset::Refused) { Demo::Reset.call }
  end

  test "deletes only the demo user's transactions, imports and merchant rules" do
    other = transactions(:one_coffee)
    counts = Demo::Reset.call(env: "development")
    assert_operator counts[:transactions], :>, 1_000
    assert_equal 0, @demo.transactions.count
    assert_equal 0, @demo.imports.count
    assert_equal 0, @demo.merchant_rules.count
    assert @demo.accounts.exists?, "accounts are kept"
    assert Transaction.exists?(other.id), "other users' rows are untouched"
  end

  test "the demo data loads again after a reset" do
    before = @demo.transactions.count
    Demo::Reset.call(env: "development")
    Demo::Seeder.call(user: @demo)
    assert_equal before, @demo.transactions.count
  end

  test "another account is reset only when named by email, and its corrections and pairs go too" do
    owner = users(:one)
    groceries = Category.find_by!(slug: "groceries")
    t = accounts(:one_checking).transactions.create!(posted_on: Date.new(2026, 11, 3), amount: "-4.00", description: "ZQX", needs_review: true)
    Categorization::Correction.apply(user: owner, transaction: t, category: groceries)
    demo_rows = @demo.transactions.count

    counts = Demo::Reset.call(env: "development", email: owner.email.upcase)
    assert_operator counts[:category_corrections], :>=, 1
    assert_equal 0, owner.transactions.count
    assert_equal 0, owner.merchant_rules.count
    assert_equal demo_rows, @demo.transactions.count, "the demo account is untouched"
  end

  test "an unknown email is refused" do
    assert_raises(Demo::Reset::Refused) { Demo::Reset.call(env: "development", email: "nobody@example.com") }
  end

  test "the demo account resets even after corrections and confirmed transfers" do
    link = @demo.transfer_links.first
    link&.update!(status: "confirmed", confirmed_at: Time.current)
    t = @demo.transactions.where(needs_review: true).first
    Categorization::Correction.apply(user: @demo, transaction: t, category: Category.find_by!(slug: "groceries")) if t
    Demo::Reset.call(env: "development")
    assert_equal 0, @demo.transactions.count
  end
end
