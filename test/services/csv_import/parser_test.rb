require "test_helper"

# I1 (CSV parser): the plan's test list for the generic format (§2.4).
class CsvImport::ParserTest < ActiveSupport::TestCase
  HEADER = "date,description,amount\n".freeze

  def parse(text)
    CsvImport::Parser.parse(text)
  end

  def one_row(line)
    result = parse(HEADER + line + "\n")
    assert result.ok?, result.file_error&.message
    result
  end

  def amount_of(text)
    result = one_row(%(2026-11-02,Coffee,"#{text}"))
    result.rows.first&.amount || result.errors.first&.fetch(:code)
  end

  test "parses a simple file" do
    result = parse(HEADER + "2026-11-02,Coffee,-4.50\n2026-11-03,Paycheck,1500\n")
    assert result.ok?
    assert_equal 2, result.rows.size
    first = result.rows.first
    assert_equal [2, Date.new(2026, 11, 2), BigDecimal("-4.50"), "Coffee", nil, nil],
                 [first.line, first.posted_on, first.amount, first.description, first.external_id, first.balance]
    assert_equal [], result.errors
    assert_not result.has_transaction_id
  end

  test "a UTF-8 BOM is ignored" do
    result = parse("﻿" + HEADER + "2026-11-02,Coffee,-4.50\n")
    assert result.ok?
    assert_equal 1, result.rows.size
  end

  test "headers are case-insensitive, trimmed and in any order" do
    result = parse(" Amount ,DATE,Description\n-4.50,2026-11-02,Coffee\n")
    assert result.ok?
    assert_equal BigDecimal("-4.50"), result.rows.first.amount
  end

  test "a quoted comma stays inside the description" do
    assert_equal "Smith, John - rent", one_row(%(2026-11-02,"Smith, John - rent",-900)).rows.first.description
  end

  test "both date forms parse" do
    assert_equal Date.new(2026, 11, 2), one_row("2026-11-02,A,-1").rows.first.posted_on
    assert_equal Date.new(2026, 11, 2), one_row("11/02/2026,A,-1").rows.first.posted_on
  end

  test "bad dates are row errors" do
    ["2026-13-01", "2026-02-30", "02/30/2026", "Nov 2 2026", "2026-11-02T10:00", "20261102"].each do |d|
      assert_equal [{ line: 2, code: "bad_date" }], one_row("#{d},A,-1").errors, d
    end
    assert_equal [{ line: 2, code: "missing_date" }], one_row(",A,-1").errors
  end

  test "month-first dates with one- or two-digit month and day parse (PO-18 change)" do
    { "2/3/2026" => Date.new(2026, 2, 3), "12/31/2026" => Date.new(2026, 12, 31),
      "2/29/2028" => Date.new(2028, 2, 29), "02/03/2026" => Date.new(2026, 2, 3),
      "2/03/2026" => Date.new(2026, 2, 3) }.each do |text, date|
      assert_equal date, one_row("#{text},A,-1").rows.first&.posted_on, text
    end
  end

  test "impossible, two-digit-year and day-first dates are rejected" do
    ["2/30/2026", "2/3/26", "13/1/2026", "31/12/2026", "2/3/026", "002/3/2026", "2026-2-3"].each do |d|
      assert_equal [{ line: 2, code: "bad_date" }], one_row("#{d},A,-1").errors, d
    end
  end

  test "leap day parses only in a leap year" do
    assert_equal Date.new(2028, 2, 29), one_row("2028-02-29,A,-1").rows.first.posted_on
    assert_equal "bad_date", one_row("2027-02-29,A,-1").errors.first[:code]
  end

  test "amount formats" do
    assert_equal BigDecimal("-12.34"), amount_of("(12.34)")
    assert_equal BigDecimal("-12.34"), amount_of("($12.34)")
    assert_equal BigDecimal("1234.56"), amount_of("$1,234.56")
    assert_equal BigDecimal("-1234.56"), amount_of("-$1,234.56")
    assert_equal BigDecimal("-1234.56"), amount_of("$-1,234.56")
    assert_equal BigDecimal("12"), amount_of("+12")
    assert_equal BigDecimal("1234567.5"), amount_of("1,234,567.5")
    assert_equal BigDecimal("1234"), amount_of("1234")
  end

  test "bad amounts are row errors" do
    ["12.345", "abc", "1,23.00", "12,34", "--5", "(-5)", "-(5)", "5-", ".50", "$", "1.2.3", "€5"].each do |a|
      assert_equal "bad_amount", amount_of(a), a
    end
    assert_equal "amount_too_large", amount_of("10000000000.00")
    assert_equal BigDecimal("9999999999.99"), amount_of("9999999999.99")
    assert_equal [{ line: 2, code: "missing_amount" }], one_row("2026-11-02,A,").errors
  end

  test "zero amounts are skipped with a warning" do
    result = one_row("2026-11-02,Card verification,0.00")
    assert_equal [], result.rows
    assert_equal [], result.errors
    assert_equal [{ line: 2, code: "zero_amount" }], result.warnings
  end

  test "description rules" do
    assert_equal "Corner Shop", one_row("2026-11-02,  Corner   Shop  ,-1").rows.first.description
    assert_equal [{ line: 2, code: "missing_description" }], one_row("2026-11-02,  ,-1").errors
    assert_equal [{ line: 2, code: "description_too_long" }], one_row("2026-11-02,#{'x' * 256},-1").errors
    assert_equal 255, one_row("2026-11-02,#{'x' * 255},-1").rows.first.description.length
  end

  test "a missing required header rejects the whole file and names the required headers" do
    result = parse("date,memo,amount\n2026-11-02,Coffee,-4.50\n")
    assert_not result.ok?
    assert_equal "missing_headers", result.file_error.code
    assert_includes result.file_error.message, "date, description, amount"
    assert_includes result.file_error.message, "Missing: description"
    assert_equal [], result.rows
  end

  test "extra columns are ignored and reported" do
    result = parse("date,description,amount,Memo,category\n2026-11-02,Coffee,-4.50,x,y\n")
    assert result.ok?
    assert_equal %w[memo category], result.extra_columns
    assert_equal 1, result.rows.size
  end

  test "transaction_id present: stored as external_id; blank values are nil" do
    result = parse("date,description,amount,transaction_id\n2026-11-02,A,-1, TX-9 \n2026-11-03,B,-2,\n")
    assert result.has_transaction_id
    assert_equal ["TX-9", nil], result.rows.map(&:external_id)
    assert_equal [{ line: 2, code: "transaction_id_too_long" }],
                 parse("date,description,amount,transaction_id\n2026-11-02,A,-1,#{'9' * 256}\n").errors
  end

  test "transaction_id absent: no external ids" do
    result = one_row("2026-11-02,A,-1")
    assert_not result.has_transaction_id
    assert_nil result.rows.first.external_id
  end

  test "optional balance is read when valid and dropped when not" do
    result = parse("date,description,amount,balance\n2026-11-02,A,-1,\"$1,000.00\"\n2026-11-03,B,-2,n/a\n")
    assert_equal [BigDecimal("1000"), nil], result.rows.map(&:balance)
    assert_equal [], result.errors
  end

  test "empty files are rejected" do
    ["", "   \n", "﻿"].each do |text|
      assert_equal "empty_file", parse(text).file_error.code, text.inspect
    end
    assert_equal "no_rows", parse(HEADER).file_error.code
    assert_equal "no_rows", parse(HEADER + ",,\n\n").file_error.code
  end

  test "bad rows are reported by line number without stopping the others" do
    text = HEADER + "2026-11-02,A,-1\n2026-99-99,B,-2\n2026-11-04,C,oops\n\n2026-11-05,D,-4\n"
    result = parse(text)
    assert_equal [2, 6], result.rows.map(&:line)
    assert_equal [{ line: 3, code: "bad_date" }, { line: 4, code: "bad_amount" }], result.errors
  end

  test "errors and warnings never contain row text" do
    result = parse(HEADER + "bad,SECRET MERCHANT,-1\n2026-11-02,OTHER SECRET,0\n")
    (result.errors + result.warnings).each { |e| assert_equal %i[code line], e.keys.sort }
    assert_no_match(/SECRET/, (result.errors + result.warnings).inspect)
  end

  test "row errors fit the imports.row_errors rules" do
    result = parse(HEADER + "bad,A,-1\n")
    import = accounts(:one_checking).imports.new(filename: "x.csv", row_errors: result.errors)
    assert import.valid?, import.errors.full_messages.join
  end

  test "duplicate headers reject the file" do
    assert_equal "duplicate_headers", parse("date,description,amount,Amount\n2026-11-02,A,-1,-1\n").file_error.code
  end

  test "an unclosed quote rejects the file" do
    assert_equal "malformed_csv", parse(HEADER + %(2026-11-02,"Coffee,-4.50\n)).file_error.code
  end

  test "non-UTF-8 files are rejected" do
    latin1 = (HEADER + "2026-11-02,Caf\xE9,-4.50\n").b
    assert_equal "invalid_encoding", parse(latin1).file_error.code
  end

  test "size and row limits" do
    assert_equal "file_too_large", parse(HEADER + ("x" * (2 * 1024 * 1024))).file_error.code
    rows = Array.new(10_001) { "2026-11-02,A,-1" }.join("\n")
    assert_equal "too_many_rows", parse(HEADER + rows).file_error.code
    assert parse(HEADER + Array.new(10_000) { "2026-11-02,A,-1" }.join("\n")).ok?
  end

  test "the downloadable template parses cleanly" do
    result = parse(Rails.root.join("public/csv-templates/generic.csv").read)
    assert result.ok?
    assert_equal [], result.errors + result.warnings + result.extra_columns
    assert_equal [BigDecimal("1850"), BigDecimal("-64.18"), BigDecimal("-1200"), BigDecimal("-4.75")], result.rows.map(&:amount)
  end
end
