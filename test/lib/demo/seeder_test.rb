require "test_helper"

# DEMO-G (demo data generator): demo:seed goes through the real import pipeline.
class Demo::SeederTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed
    @user = User.create!(email: "demo.user@example.com", first_name: "Demo", last_name: "User")
  end

  test "imports every file through the import pipeline, with duplicates and row errors" do
    results = Demo::Seeder.call(user: @user).to_h { |name, import, cat| [name, [import, cat]] }
    g = Demo::Generator.new

    assert_equal %w[Everyday\ Checking Rainy\ Day\ Savings Venmo].sort, @user.accounts.pluck(:name).sort
    assert_equal({ "checking" => "spending", "savings" => "savings", "venmo" => "side_income" },
                 Demo::Generator::ACCOUNTS.to_h { |k, a| [k, @user.accounts.find_by!(name: a[:name]).purpose] })

    %w[checking.csv savings.csv venmo.csv].each do |name|
      assert_equal CsvImport::Parser.parse(g.files[name]).rows.size, results[name][0].inserted_count, name
    end
    overlap = results["checking-overlap.csv"][0]
    assert_equal [0, overlap.row_count], [overlap.inserted_count, overlap.duplicate_count]
    malformed = results["malformed.csv"][0]
    assert_equal [2, 3], [malformed.inserted_count, malformed.error_count]

    assert_equal g.rows.size + 2, @user.transactions.count
    assert @user.transactions.where(categorization_source: "rule").count > 500, "keyword rules place most rows"
    assert @user.transactions.where(needs_review: true).exists?, "some rows are left for review/AI"
    assert_equal 0, @user.transactions.where(categorization_source: "ai").count
    assert @user.financial_profile.present?
  end

  test "running it again imports nothing new" do
    Demo::Seeder.call(user: @user)
    assert_no_difference -> { Transaction.count } do
      results = Demo::Seeder.call(user: @user)
      assert results.all? { |_, import, _| import.inserted_count.zero? }
    end
  end

  test "rules categorize the demo data into the expected categories" do
    Demo::Seeder.call(user: @user)
    by_desc = @user.transactions.includes(:category).index_by(&:description)
    {
      "OAK PROPERTY MANAGEMENT RENT" => "rent", "NORTHWIND LABS PAYROLL" => "income",
      "NORTHSTAR STUDENT LOAN PAYMENT" => "debt-payments", "WHOLEFDS MKT #10234" => "groceries",
      "SHELL OIL 57444 XXXX1234" => "transportation", "GEICO AUTO PAYMENT" => "insurance"
    }.each { |desc, slug| assert_equal slug, by_desc.fetch(desc).category&.slug, desc }
    assert by_desc.fetch("TRANSFER TO SAVINGS 4821").needs_review, "transfers wait for TR1 / review"
  end
end
