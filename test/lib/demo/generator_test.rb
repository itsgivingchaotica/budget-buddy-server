require "test_helper"

# DEMO-G (demo data generator).
class Demo::GeneratorTest < ActiveSupport::TestCase
  def gen(**opts) = Demo::Generator.new(**opts)

  test "the same seed and end date give byte-identical files" do
    a = gen
    b = gen
    assert_equal a.files, b.files
    assert_equal a.golden_csv, b.golden_csv
  end

  test "a different seed gives different files" do
    assert_not_equal gen.files["checking.csv"], gen(seed: 1).files["checking.csv"]
  end

  test "files can be written to disk and match" do
    Dir.mktmpdir do |dir|
      g = gen
      g.write(dir)
      g.files.each { |name, text| assert_equal text, File.binread(File.join(dir, name)), name }
      assert File.exist?(File.join(dir, "golden.csv"))
    end
  end

  test "every account file parses cleanly; malformed.csv has row errors but still imports" do
    files = gen.files
    %w[checking.csv savings.csv venmo.csv checking-overlap.csv].each do |name|
      result = CsvImport::Parser.parse(files[name])
      assert result.ok?, name
      assert_empty result.errors + result.warnings, name
    end
    bad = CsvImport::Parser.parse(files["malformed.csv"])
    assert bad.ok?
    assert_equal %w[bad_date bad_amount missing_description], bad.errors.map { |e| e[:code] }
    assert_equal ["zero_amount"], bad.warnings.map { |w| w[:code] }
    assert_equal 2, bad.rows.size
  end

  test "24 months of data ending on the end date; venmo uses month-first dates" do
    g = gen
    dates = g.rows.map(&:date)
    assert_equal Demo::Generator::DEFAULT_END_ON, dates.max
    assert_operator dates.min, :>, Demo::Generator::DEFAULT_END_ON << 24
    assert_match %r{\A\d{1,2}/\d{1,2}/\d{4},}, g.files["venmo.csv"].lines[1]
  end

  test "transfer pairs: same amount, opposite sign, different accounts, 0-2 days apart" do
    pairs = gen.transfer_pairs
    assert_operator pairs.size, :>=, 40
    pairs.each do |out_row, in_row|
      assert_equal(-out_row.cents, in_row.cents)
      assert out_row.cents.negative?
      assert_not_equal out_row.account, in_row.account
      assert_includes 0..2, (in_row.date - out_row.date).to_i
      assert_equal %w[transfers transfers], [out_row.slug, in_row.slug]
    end
  end

  test "decoys look like transfers but aren't" do
    decoys = gen.decoy_pairs
    assert_operator decoys.size, :>=, 6
    decoys.each do |out_row, in_row|
      assert_equal(-out_row.cents, in_row.cents)
      assert_not_equal out_row.account, in_row.account
      assert_operator (in_row.date - out_row.date).to_i.abs, :<=, 3
      assert_not_includes [out_row.slug, in_row.slug], "transfers"
    end
  end

  test "the golden set has 300 labelled rows covering every MVP category, with noisy variants" do
    Rails.application.load_seed
    golden = gen.golden
    assert_equal 300, golden.size
    assert_equal Category.active_list.pluck(:slug).sort, golden.map(&:slug).uniq.sort
    assert golden.any? { |r| r.description.start_with?("POS PURCHASE ") }
    assert golden.any? { |r| r.description == r.description.downcase }
    header = gen.golden_csv.lines.first.strip
    assert_equal "date,description,amount,account_purpose,expected_category", header
  end

  test "contains no real personal data" do
    text = gen.files.values.join + gen.golden_csv
    assert_no_match(/@|\bhttps?:|\d{3}[-. ]\d{3}[-. ]\d{4}|\b\d{3}-\d{2}-\d{4}\b/, text, "no emails, links, phone or SSN-like numbers")
    people = text.scan(/Payment (?:from|to) ([^-\n]+?) -/).flatten.uniq
    assert people.all? { |p| p.match?(/\A[A-Z]\. [A-Z][a-z]+\z/) }, "people are initials + an invented surname only: #{people}"
    assert_empty people - Demo::Generator::PAYERS
  end
end
