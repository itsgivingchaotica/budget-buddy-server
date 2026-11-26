require "test_helper"

# AI2 (Claude categorization): the deterministic transfer pre-check.
class Categorization::TransferCheckTest < ActiveSupport::TestCase
  def like?(text, names = []) = Categorization::TransferCheck.transfer_like?(Categorization::MerchantKey.for(Transaction.normalize_description(text)), names)

  test "transfer wording" do
    ["TRANSFER TO SAVINGS 4821", "Transfer from Checking", "ONLINE TRANSFER TO CHK", "VENMO CASHOUT",
     "VENMO CASHOUT PPD ID 5264", "Cash Out", "CASH  OUT TO BANK"].each { |t| assert like?(t), t }
  end

  test "not transfers" do
    ["ZELLE TO J SMITH", "Payment from A. Rivera - logo design", "AMAZON MKTPLACE PMTS", "WIRE TRANSFER FEE",
     "TRANSFERWISE", "CASHOUTS ARCADE", "TRADER JOE'S #552", "BALANCE TRANSFER"].each { |t| assert_not like?(t), t }
  end

  test "names of the user's other accounts, whole words, 4+ characters" do
    assert like?("ONLINE PMT RAINY DAY SAVINGS", ["Rainy Day Savings"])
    assert like?("Payment to  rainy   day savings", ["Rainy  Day Savings"])
    assert_not like?("RAINY DAY SAVINGSTORE", ["Rainy Day Savings"])
    assert_not like?("BOA SUPERMARKET", ["BoA"]), "names under 4 characters are ignored"
    assert_not like?("COFFEE", [])
  end
end
