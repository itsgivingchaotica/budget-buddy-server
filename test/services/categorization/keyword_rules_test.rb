require "test_helper"

# AI1 (rules-based categorization): merchant keys and the keyword rule list.
class Categorization::KeywordRulesTest < ActiveSupport::TestCase
  def key(text) = Categorization::MerchantKey.for(Transaction.normalize_description(text))
  def match(text, amount = "-10") = Categorization::KeywordRules.match(key(text), BigDecimal(amount))

  test "merchant keys drop card-processor and POS prefixes" do
    assert_equal "BLUE BOTTLE", key("SQ *Blue Bottle #22")
    assert_equal "BLUE BOTTLE", key("TST* BLUE BOTTLE")
    assert_equal "BLUE BOTTLE", key("POS PURCHASE BLUE BOTTLE")
    assert_equal "BLUE BOTTLE", key("DEBIT CARD PURCHASE BLUE BOTTLE XXXX1234")
    assert_equal "SQ", key("SQ"), "never strips down to nothing"
  end

  test "common merchants" do
    {
      "UBER EATS PENDING" => "dining-out", "UBER TRIP 1234" => "transportation", "Shell Oil 57444" => "transportation",
      "NETFLIX.COM" => "subscriptions", "Spotify USA" => "subscriptions", "KROGER #123" => "groceries",
      "Comcast Xfinity" => "utilities", "AT&T Wireless" => "utilities", "GEICO AUTO" => "insurance",
      "CVS/PHARMACY #0123" => "healthcare", "Home Depot 4410" => "home-improvement", "Delta Air Lines" => "travel",
      "AIRBNB HMQ" => "travel", "AMC THEATRES 0091" => "entertainment", "COURSERA.ORG" => "education",
      "SEPHORA 1234" => "personal-care", "UNIQLO USA" => "clothing", "1-800-FLOWERS" => "gifts",
      "OAK PROPERTY MANAGEMENT RENT" => "rent"
    }.each { |text, slug| assert_equal slug, match(text), text }
  end

  test "whole words only" do
    assert_nil match("MATTRESS FIRM"), "ATT inside a word"
    assert_nil match("BARTENDER SUPPLY"), "BART inside a word"
    assert_nil match("PARENTAL ADVISORY"), "RENT inside a word"
  end

  test "sign rules" do
    assert_equal "income", match("ACME PAYROLL", "2000")
    assert_nil match("ACME PAYROLL", "-20")
    assert_equal "debt-payments", match("CITI CARD PAYMENT", "-200")
    assert_nil match("CITI CARD PAYMENT", "200")
  end

  test "unknown merchants and transfers aren't matched" do
    assert_nil match("ZQX HOLDINGS")
    assert_nil match("TRANSFER TO SAVINGS")
    assert_nil match("ZELLE TO J SMITH")
  end

  test "every rule points at a seeded MVP category, never Transfers" do
    Rails.application.load_seed
    active = Category.active_list.pluck(:slug, :kind).to_h
    Categorization::KeywordRules::RULES.each do |rule|
      assert active.key?(rule.slug), "#{rule.slug} isn't an active seeded category"
      assert_not_equal "transfer", active[rule.slug]
    end
  end
end
