require "test_helper"

class FinancialProfileTest < ActiveSupport::TestCase
  test "the week starts on Monday (wday 1) by default" do
    profile = users(:one).create_financial_profile!
    assert_equal FinancialProfile::MONDAY, profile.week_starts_on
    assert_equal 1, Date.new(2026, 11, 16).wday # 2026-11-16 is a Monday
  end

  test "week_starts_on must be a wday (0-6)" do
    assert_not FinancialProfile.new(user: users(:one), week_starts_on: 7).valid?
  end

  test "time_zone must be an IANA zone" do
    assert FinancialProfile.new(user: users(:one), time_zone: "America/New_York").valid?
    assert_not FinancialProfile.new(user: users(:one), time_zone: "Eastern Time").valid?
  end
end
