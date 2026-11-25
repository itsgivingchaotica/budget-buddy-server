require "csv"
require "date"
require "fileutils"

module Demo
  # DEMO-G (demo data generator): deterministic synthetic bank exports for
  # one fictional persona, in the generic CSV format (plan §2.4).
  #
  # Same seed + same end date => byte-identical files, so tests can rely on
  # them. Everything is fictional: an invented employer, invented people
  # (initials only) and invented local businesses. Well-known chain names
  # appear only as merchants, so the keyword rules (AI1) have something
  # realistic to match.
  #
  # Files (Generator#files => { "name.csv" => csv_text }):
  #   checking.csv          24 months: paychecks, rent, bills, card spending
  #                         with processor/store-number noise, loan payments
  #   savings.csv           monthly transfer in, occasional transfer out, interest
  #   venmo.csv             side-job income, dinner splits, cash-outs
  #                         (month-first M/D/YYYY dates, to exercise the parser)
  #   checking-overlap.csv  a second export of checking's last 60 days
  #                         (importing it adds nothing: duplicate detection)
  #   malformed.csv         a few good rows plus bad date/amount/description rows
  #
  # Transfers are generated as pairs (same amount, opposite sign, different
  # accounts, 0-2 day gap) and recorded in #transfer_pairs, plus decoys (same
  # amount within 3 days, not a transfer) in #decoy_pairs, for TR1
  # (transfer matching).
  #
  # #golden is the labelled set for EV1 (categorization eval): about 300 rows
  # with the expected category slug, including noisy and ambiguous ones.
  class Generator
    Row = Struct.new(:account, :date, :description, :cents, :slug, keyword_init: true)

    ACCOUNTS = {
      "checking" => { name: "Everyday Checking", kind: "checking", purpose: "spending" },
      "savings" => { name: "Rainy Day Savings", kind: "savings", purpose: "savings" },
      "venmo" => { name: "Venmo", kind: "p2p", purpose: "side_income" }
    }.freeze

    # slug => [[description, min_cents, max_cents], ...]
    SPENDING = {
      "groceries" => [["WHOLEFDS MKT #10234", 2_500, 14_000], ["TRADER JOE'S #552", 1_800, 9_000],
                      ["SAFEWAY #1887", 2_000, 11_000], ["Maple Street Grocer", 900, 4_500]],
      "dining-out" => [["SQ *BLUE KETTLE CAFE", 450, 1_600], ["STARBUCKS 08812", 400, 1_200],
                       ["CHIPOTLE 2214", 1_100, 2_400], ["TST* Lantern Noodle House", 1_800, 5_200],
                       ["DOORDASH*PIZZA PALACE", 2_200, 4_800]],
      "transportation" => [["SHELL OIL 57444 XXXX1234", 3_000, 6_500], ["UBER TRIP", 900, 3_400],
                           ["LYFT RIDE", 1_000, 2_800], ["CITY PARKING 33", 300, 1_800]],
      "healthcare" => [["CVS/PHARMACY #0123", 600, 4_500], ["WALGREENS #4410", 500, 3_000], ["Pinecrest Dental", 9_000, 24_000]],
      "personal-care" => [["SQ *FADE BARBER", 2_500, 4_000], ["SEPHORA 1234", 1_500, 7_000]],
      "clothing" => [["UNIQLO USA", 2_000, 9_000], ["OLD NAVY 7731", 1_500, 6_000]],
      "entertainment" => [["AMC THEATRES 0091", 1_400, 3_800], ["TICKETMASTER", 4_000, 16_000]],
      "home-improvement" => [["HOME DEPOT 4410", 1_200, 15_000], ["IKEA", 3_000, 25_000]],
      "gifts" => [["1-800-FLOWERS", 4_000, 9_000]],
      "other" => [["AMAZON MKTPLACE PMTS", 1_000, 8_000], ["TARGET 00012", 1_500, 9_000]]
    }.freeze

    PAYERS = ["A. Rivera", "K. Osei", "M. Lindqvist", "R. Tanaka", "S. Okafor", "J. Moreau"].freeze

    attr_reader :rows, :transfer_pairs, :decoy_pairs

    DEFAULT_SEED = 20_261_124
    DEFAULT_END_ON = Date.new(2026, 11, 20)

    def initialize(seed: DEFAULT_SEED, end_on: DEFAULT_END_ON, months: 24)
      @rng = Random.new(seed)
      @end_on = end_on
      @start_on = (end_on << months) + 1
      @rows = []
      @transfer_pairs = []
      @decoy_pairs = []
      generate
    end

    def files
      {
        "checking.csv" => csv(rows_for("checking"), us_dates: false),
        "savings.csv" => csv(rows_for("savings"), us_dates: false),
        "venmo.csv" => csv(rows_for("venmo"), us_dates: true),
        "checking-overlap.csv" => csv(rows_for("checking").select { |r| r.date > @end_on - 60 }, us_dates: false),
        "malformed.csv" => malformed
      }
    end

    def write(dir)
      FileUtils.mkdir_p(dir)
      files.each { |name, text| File.binwrite(File.join(dir, name), text) }
      File.binwrite(File.join(dir, "golden.csv"), golden_csv)
      dir
    end

    # About 300 labelled rows: a fixed-seed sample of every category, plus
    # noisy variants (case, spacing, processor prefixes).
    def golden
      @golden ||= begin
        pick = Random.new(7)
        by_slug = @rows.group_by(&:slug)
        sample = by_slug.keys.sort.flat_map do |slug|
          group = by_slug[slug].sort_by { |r| [r.date, r.account, r.description, r.cents] }
          group.shuffle(random: pick).first(16)
        end
        wanted = [300 - sample.size, 0].max
        stride = wanted.zero? ? 1 : [sample.size / wanted, 1].max
        noisy = sample.select.with_index { |_, i| (i % stride).zero? }.first(wanted).map.with_index do |r, i|
          r.dup.tap { |n| n.description = noisify(r.description, i) }
        end
        (sample + noisy).first(300)
      end
    end

    def golden_csv
      CSV.generate(+"", row_sep: "\n") do |out|
        out << %w[date description amount account_purpose expected_category]
        golden.each { |r| out << [r.date.iso8601, r.description, money(r.cents), ACCOUNTS[r.account][:purpose], r.slug] }
      end
    end

    private

    def add(account, date, description, cents, slug)
      return if date < @start_on || date > @end_on

      @rows << Row.new(account:, date:, description:, cents:, slug:)
      @rows.last
    end

    def between(min, max) = @rng.rand(min..max)

    def generate
      each_month do |first|
        add("checking", first, "OAK PROPERTY MANAGEMENT RENT", -185_000, "rent")
        add("checking", first + 4, "COMCAST XFINITY", -between(7_900, 8_900), "utilities")
        add("checking", first + 9, "PG&E WEB ONLINE", -between(6_000, 14_000), "utilities")
        add("checking", first + 11, "VERIZON WIRELESS", -6_500, "utilities")
        add("checking", first + 2, "NETFLIX.COM", -1_549, "subscriptions")
        add("checking", first + 6, "SPOTIFY USA", -1_199, "subscriptions")
        add("checking", first + 14, "ICLOUD STORAGE", -299, "subscriptions")
        add("checking", first + 19, "NORTHSTAR STUDENT LOAN PAYMENT", -32_000, "debt-payments")
        add("checking", first + 3, "COURSERA.ORG", -4_900, "education") if first.month.odd?
        add("checking", first + 7, "GEICO AUTO PAYMENT", -61_800, "insurance") if [1, 7].include?(first.month)
        add("checking", first + 12, "DELTA AIR LINES", -between(22_000, 48_000), "travel") if [3, 8].include?(first.month)
        add("checking", first + 13, "AIRBNB HMQ", -between(30_000, 65_000), "travel") if first.month == 8
        add("savings", last_day(first), "INTEREST PAID", between(80, 450), "income")

        monthly_transfer(first)
        card_spending(first)
        venmo_month(first)
      end
      paychecks
      decoys
    end

    def each_month
      month = Date.new(@start_on.year, @start_on.month, 1)
      while month <= @end_on
        yield month
        month >>= 1
      end
    end

    def last_day(first) = (first >> 1) - 1

    def paychecks
      day = Date.new(@start_on.year, @start_on.month, 1) + 4
      day += 14 while day < @start_on
      while day <= @end_on
        add("checking", day, "NORTHWIND LABS PAYROLL", between(228_000, 236_000), "income")
        day += 14
      end
    end

    def monthly_transfer(first)
      cents = between(20, 40) * 1_000
      pair(first + 14, "checking", "TRANSFER TO SAVINGS 4821", "savings", "TRANSFER FROM CHECKING 1190", cents)
      return unless (first.month % 4).zero?

      pair(first + 24, "savings", "TRANSFER TO CHECKING 1190", "checking", "TRANSFER FROM SAVINGS 4821", between(10, 30) * 1_000)
    end

    # Money leaves `from` and arrives in `to` 0-2 days later.
    def pair(date, from, out_description, to, in_description, cents)
      out_row = add(from, date, out_description, -cents, "transfers")
      in_row = add(to, date + between(0, 2), in_description, cents, "transfers")
      @transfer_pairs << [out_row, in_row] if out_row && in_row
    end

    def card_spending(first)
      days = last_day(first).day
      SPENDING.each do |slug, merchants|
        visits = case slug
                 when "groceries" then 6
                 when "dining-out" then 7
                 when "transportation" then 5
                 when "gifts" then first.month == 12 ? 2 : 0
                 else between(0, 2)
                 end
        visits.times do
          description, min, max = merchants[between(0, merchants.size - 1)]
          add("checking", first + between(0, days - 1), description, -between(min, max), slug)
        end
      end
      # A refund now and then: money in, same category.
      add("checking", first + 20, "TRADER JOE'S #552", between(300, 1_500), "groceries") if first.month == 5
    end

    def venmo_month(first)
      2.times do
        payer = PAYERS[between(0, PAYERS.size - 1)]
        add("venmo", first + between(0, 25), "Payment from #{payer} - logo design", between(6_000, 25_000), "income")
      end
      friend = PAYERS[between(0, PAYERS.size - 1)]
      add("venmo", first + between(0, 25), "Payment to #{friend} - dinner", -between(1_500, 4_500), "dining-out")

      cash_out = between(80, 300) * 100
      pair(first + 27, "venmo", "VENMO CASHOUT", "checking", "VENMO CASHOUT PPD ID 5264", cash_out)
    end

    # Same amount, opposite sign, different accounts, within 3 days, but not
    # a transfer: a friend pays you back on Venmo the day you buy something
    # of the same price on your card.
    def decoys
      each_month do |first|
        next unless (first.month % 3).zero?

        cents = between(30, 90) * 100 + 50
        a = add("venmo", first + 9, "Payment from #{PAYERS[between(0, PAYERS.size - 1)]} - concert tickets", cents, "income")
        b = add("checking", first + 10, "TICKETMASTER", -cents, "entertainment")
        @decoy_pairs << [b, a] if a && b
      end
    end

    def rows_for(account)
      @rows.select { |r| r.account == account }
           .each_with_index.sort_by { |r, i| [r.date, i] }.map(&:first)
    end

    def money(cents)
      sign = cents.negative? ? "-" : ""
      format("%s%d.%02d", sign, cents.abs / 100, cents.abs % 100)
    end

    def csv(rows, us_dates:)
      CSV.generate(+"", row_sep: "\n") do |out|
        out << %w[date description amount]
        rows.each do |r|
          date = us_dates ? "#{r.date.month}/#{r.date.day}/#{r.date.year}" : r.date.iso8601
          out << [date, r.description, money(r.cents)]
        end
      end
    end

    def malformed
      CSV.generate(+"", row_sep: "\n") do |out|
        out << %w[date description amount]
        out << [(@end_on - 3).iso8601, "Maple Street Grocer", "-23.10"]
        out << ["2026-13-40", "Corner Kiosk", "-4.00"]      # bad date
        out << [(@end_on - 2).iso8601, "Corner Kiosk", "four dollars"] # bad amount
        out << [(@end_on - 2).iso8601, "", "-6.00"]         # missing description
        out << [(@end_on - 1).iso8601, "Card verification", "0.00"] # zero: skipped
        out << [(@end_on - 1).iso8601, "SQ *BLUE KETTLE CAFE", "(5.25)"]
      end
    end

    def noisify(description, i)
      case i % 4
      when 0 then description.downcase
      when 1 then "POS PURCHASE #{description}"
      when 2 then description.gsub(" ", "  ") + " #{1000 + i}"
      else "#{description} XXXX#{4000 + i}"
      end
    end
  end
end
