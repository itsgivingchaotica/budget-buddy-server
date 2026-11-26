require "test_helper"

# I2 (import endpoint): POST /accounts/:account_id/imports, with the plan's
# duplicate-detection cases (§2.3).
class ImportsControllerTest < ActionDispatch::IntegrationTest
  HEADER = "date,description,amount\n".freeze
  NOV = (HEADER + <<~CSV).freeze
    2026-11-01,Paycheck,1850.00
    2026-11-02,Corner Grocery #214,-64.18
    2026-11-02,Coffee Shop,-4.75
    2026-11-02,Coffee Shop,-4.75
    2026-11-03,Rent,-1200.00
  CSV

  setup { @account = accounts(:one_checking) }

  def upload(text, filename: "nov.csv", type: "text/csv")
    Rack::Test::UploadedFile.new(StringIO.new(text), type, original_filename: filename)
  end

  def import!(text, account: @account, **opts)
    post api_v1_account_imports_url(account), params: { file: upload(text, **opts) }, headers: auth_headers
    response.parsed_body
  end

  test "imports a file and returns the summary" do
    body = import!(NOV)
    assert_response :created
    assert_equal({ "filename" => "nov.csv", "status" => "completed", "row_count" => 5, "inserted_count" => 5,
                   "duplicate_count" => 0, "error_count" => 0, "skipped_count" => 0,
                   "data_from" => "2026-11-01", "data_through" => "2026-11-03" },
                 body.slice(*%w[filename status row_count inserted_count duplicate_count error_count skipped_count
                                data_from data_through]))
    stored = @account.transactions.where(import_id: body["id"])
    assert_equal 5, stored.count
    assert_equal [BigDecimal("-4.75")] * 2, stored.where(normalized_description: "COFFEE SHOP").pluck(:amount)
    assert_equal [1, 2], stored.where(normalized_description: "COFFEE SHOP").order(:occurrence).pluck(:occurrence)
    assert stored.all? { |t| t.categorization_source == "none" && t.category_id.nil? }
  end

  test "the same file again inserts nothing" do
    import!(NOV)
    body = import!(NOV)
    assert_response :created
    assert_equal [0, 5], body.values_at("inserted_count", "duplicate_count")
    assert_equal 6, @account.transactions.count # 5 + the fixture row
  end

  test "the same rows rearranged insert nothing" do
    import!(NOV)
    lines = NOV.lines
    body = import!(lines.first + lines.drop(1).reverse.join)
    assert_equal [0, 5], body.values_at("inserted_count", "duplicate_count")
  end

  test "overlapping files insert only the new rows" do
    import!(NOV)
    body = import!(HEADER + "2026-11-03,Rent,-1200.00\n2026-11-04,Gas Station,-40.00\n2026-11-05,Pharmacy,-12.00\n")
    assert_equal [2, 1], body.values_at("inserted_count", "duplicate_count")
  end

  test "a third identical row in a later file is kept" do
    import!(NOV)
    body = import!(HEADER + "2026-11-02,Coffee Shop,-4.75\n" * 3)
    assert_equal [1, 2], body.values_at("inserted_count", "duplicate_count")
  end

  test "the same row in two different accounts is kept in both" do
    savings = users(:one).accounts.create!(name: "Savings", kind: "savings", purpose: "savings")
    import!(NOV)
    body = import!(NOV, account: savings)
    assert_equal 5, body["inserted_count"]
  end

  test "rows with a bank transaction_id are keyed on it" do
    csv = "date,description,amount,transaction_id\n" \
          "2026-11-02,Coffee Shop,-4.75,TX-1\n2026-11-02,Coffee Shop,-4.75,TX-2\n"
    assert_equal 2, import!(csv)["inserted_count"]
    again = import!("date,description,amount,transaction_id\n2026-11-02,Coffee Shop,-4.75,TX-3\n" \
                    "2026-11-09,Coffee Shop renamed,-4.75,TX-1\n")
    assert_equal [1, 1], again.values_at("inserted_count", "duplicate_count")
  end

  test "bad rows are reported by line and code and stored without row text" do
    body = import!(HEADER + "2026-11-02,Coffee,-4.75\nnot-a-date,SECRET SHOP,-1\n2026-11-03,Zero,0\n")
    assert_equal [1, 1, 1], body.values_at("inserted_count", "error_count", "skipped_count")
    assert_equal [{ "line" => 3, "code" => "bad_date" }], body["row_errors"]
    assert_equal [{ "line" => 4, "code" => "zero_amount" }], body["warnings"]
    assert_equal [{ "line" => 3, "code" => "bad_date" }], Import.find(body["id"]).row_errors
    assert_no_match(/SECRET/, Import.find(body["id"]).attributes.to_json)
  end

  test "extra columns are reported" do
    assert_equal ["memo"], import!("date,description,amount,memo\n2026-11-02,Coffee,-4.75,x\n")["extra_columns"]
  end

  test "whole-file problems are 422 and store nothing" do
    {
      ["", {}] => "empty_file",
      ["date,memo,amount\n2026-11-02,A,-1\n", {}] => "missing_headers",
      [NOV, { filename: "nov.xlsx" }] => "wrong_file_type",
      [NOV, { type: "application/pdf" }] => "wrong_file_type",
      [HEADER + ("x" * (2 * 1024 * 1024)), {}] => "file_too_large"
    }.each do |(text, opts), code|
      assert_no_difference -> { Import.count + Transaction.count } do
        body = import!(text, **opts)
        assert_response :unprocessable_entity
        assert_equal code, body["error"]
      end
    end
  end

  test "a missing file is 422" do
    post api_v1_account_imports_url(@account), params: {}, headers: auth_headers
    assert_response :unprocessable_entity
    assert_equal "file_missing", response.parsed_body["error"]
  end

  test "an archived account can't be imported into" do
    @account.archive!
    assert_no_difference -> { Import.count } do
      assert_equal "account_archived", import!(NOV)["error"]
    end
  end

  test "importing into another user's account is 404 and stores nothing" do
    assert_no_difference -> { Import.count + Transaction.count } do
      import!(NOV, account: accounts(:two_checking))
      assert_response :not_found
    end
  end

  test "the accounts list shows data_through and transaction_count" do
    import!(NOV)
    get api_v1_accounts_url, headers: auth_headers, as: :json
    mine = response.parsed_body.find { |a| a["id"] == @account.id }
    assert_equal ["2026-11-03", 6], mine.values_at("data_through", "transaction_count") # 5 imported + 1 fixture
    savings = users(:one).accounts.create!(name: "Empty savings", kind: "savings", purpose: "savings")
    get api_v1_account_url(savings), headers: auth_headers, as: :json
    assert_equal [nil, 0], response.parsed_body.values_at("data_through", "transaction_count")
    get api_v1_account_url(@account), headers: auth_headers, as: :json
    assert_equal "2026-11-03", response.parsed_body["data_through"]
  end

  test "10,000 rows import in under 5 seconds" do
    rows = Array.new(10_000) { |i| "2026-#{format('%02d', (i % 12) + 1)}-01,Merchant #{i} Ltd,-#{(i % 500) + 1}.25" }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    body = import!(HEADER + rows.join("\n") + "\n")
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_equal 10_000, body["inserted_count"]
    assert_operator elapsed, :<, 5.0, "took #{elapsed.round(2)} s"
  end

  test "imported rows are categorized: memory, then rules, the rest to review (AI1)" do
    groceries = Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 1)
    income = Category.create!(name: "Income", slug: "income", kind: "income", active: true, position: 2)
    rent = Category.create!(name: "Rent", slug: "rent", kind: "spending", fixed_variable: "fixed", active: true, position: 3)
    users(:one).merchant_rules.create!(merchant_key: "CORNER GROCERY", category: groceries)
    body = import!(HEADER + "2026-11-01,ACME PAYROLL,1850.00\n2026-11-02,Corner Grocery #214,-64.18\n" \
                            "2026-11-03,Rent,-1200.00\n2026-11-04,ZQX Holdings,-9.99\n")
    assert_equal({ "memory" => 1, "rule" => 2, "ai" => 0, "needs_review" => 1 }, body["categorized"].slice("memory", "rule", "ai", "needs_review"))
    rows = @account.transactions.where(import_id: body["id"]).index_by(&:description)
    assert_equal [income.id, "rule"], rows["ACME PAYROLL"].then { |t| [t.category_id, t.categorization_source] }
    assert_equal [groceries.id, "memory"], rows["Corner Grocery #214"].then { |t| [t.category_id, t.categorization_source] }
    assert_equal rent.id, rows["Rent"].category_id
    assert rows["ZQX Holdings"].needs_review
    assert_equal "none", transactions(:one_coffee).reload.categorization_source, "rows from other imports untouched"
  end
end
