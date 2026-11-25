require "csv"
require "bigdecimal"

module CsvImport
  # I1 (CSV parser): reads the one generic CSV format (plan §2.4, PO-18) into
  # plain rows. It doesn't touch the database, normalize descriptions or
  # number duplicates; the import step (I2) does that.
  #
  # Format:
  #   - UTF-8 (a BOM is allowed), comma-delimited, RFC 4180 quoting, header row.
  #   - Headers are case-insensitive, surrounding spaces ignored, any order.
  #     Required: date, description, amount. Optional: transaction_id, balance.
  #     Other columns are ignored and listed in `extra_columns`.
  #   - date: YYYY-MM-DD, or month first as M/D/YYYY (one- or two-digit
  #     month and day, so MM/DD/YYYY too; PO-18 change, 2026-11-24).
  #     Two-digit years and day-first dates are rejected.
  #   - amount: signed, negative = money out. "$", thousands separators and
  #     "(12.34)" for -12.34 are allowed; at most 2 decimals. Zero rows are
  #     skipped with a warning.
  #
  # Whole-file problems (empty, too big, missing headers...) set `file_error`
  # and return no rows. A bad row is reported by line number and error code
  # and doesn't stop the others. Line numbers count CSV records, with the
  # header as line 1 (the same as a spreadsheet's row numbers).
  #
  # Errors and warnings carry only { line, code }, never row text, so they
  # can be stored on the import as is (AD13).
  class Parser
    MAX_BYTES = 2 * 1024 * 1024
    MAX_ROWS = 10_000
    REQUIRED_HEADERS = %w[date description amount].freeze
    OPTIONAL_HEADERS = %w[transaction_id balance].freeze
    MAX_DESCRIPTION = 255
    MAX_TRANSACTION_ID = 255
    # decimal(12,2): the largest storable magnitude is 9,999,999,999.99.
    MAX_ABS_AMOUNT = BigDecimal("9999999999.99")

    ISO_DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/
    US_DATE = %r{\A(\d{1,2})/(\d{1,2})/(\d{4})\z}
    AMOUNT = /\A(?<sign>[-+])?\$?(?<sign2>-)?(?<int>\d{1,3}(?:,\d{3})+|\d+)(?:\.(?<dec>\d{1,2}))?\z/

    Row = Data.define(:line, :posted_on, :amount, :description, :external_id, :balance)

    FileError = Data.define(:code, :message)

    Result = Data.define(:rows, :errors, :warnings, :extra_columns, :file_error, :has_transaction_id) do
      def ok?
        file_error.nil?
      end
    end

    def self.parse(content)
      new(content).parse
    end

    def initialize(content)
      @content = content.to_s
    end

    def parse
      return file_error("file_too_large", "The file is over 2 MB.") if @content.bytesize > MAX_BYTES

      text = @content.dup.force_encoding(Encoding::UTF_8)
      return file_error("invalid_encoding", "The file isn't UTF-8 text.") unless text.valid_encoding?

      text = text.delete_prefix("﻿")
      return file_error("empty_file", "The file is empty.") if text.strip.empty?

      parse_records(text)
    rescue CSV::MalformedCSVError
      file_error("malformed_csv", "The file isn't valid CSV (check for an unclosed quote).")
    end

    private

    def parse_records(text)
      records = CSV.parse(text)
      header = records.shift.map { |h| h.to_s.strip.downcase }

      if header.reject(&:empty?).tally.any? { |_, n| n > 1 }
        return file_error("duplicate_headers", "A column name appears more than once.")
      end

      missing = REQUIRED_HEADERS - header
      if missing.any?
        return file_error("missing_headers",
                          "Required columns: #{REQUIRED_HEADERS.join(', ')}. Missing: #{missing.join(', ')}.")
      end

      data = records.each_with_index.map { |fields, i| [i + 2, fields] }
                    .reject { |_, fields| fields.all? { |f| f.to_s.strip.empty? } }
      return file_error("no_rows", "The file has a header row but no transactions.") if data.empty?
      return file_error("too_many_rows", "The file has more than #{MAX_ROWS} rows.") if data.size > MAX_ROWS

      index = header.each_with_index.to_h
      rows = []
      errors = []
      warnings = []

      data.each do |line, fields|
        value = ->(name) { index.key?(name) ? fields[index[name]].to_s.strip : "" }
        outcome = parse_row(line, value)
        case outcome
        in Row then rows << outcome
        in [:error, code] then errors << { line:, code: }
        in [:warning, code] then warnings << { line:, code: }
        end
      end

      Result.new(rows:, errors:, warnings:, extra_columns: header - REQUIRED_HEADERS - OPTIONAL_HEADERS - [""],
                 file_error: nil, has_transaction_id: header.include?("transaction_id"))
    end

    # Returns a Row, [:error, code] or [:warning, code]. One code per row:
    # the first problem found, checked in the order date, description, amount.
    def parse_row(line, value)
      return [:error, "missing_date"] if value.("date").empty?

      posted_on = parse_date(value.("date"))
      return [:error, "bad_date"] if posted_on.nil?

      description = value.("description").gsub(/\s+/, " ")
      return [:error, "missing_description"] if description.empty?
      return [:error, "description_too_long"] if description.length > MAX_DESCRIPTION

      return [:error, "missing_amount"] if value.("amount").empty?

      amount = parse_amount(value.("amount"))
      return [:error, "bad_amount"] if amount.nil?
      return [:error, "amount_too_large"] if amount.abs > MAX_ABS_AMOUNT
      return [:warning, "zero_amount"] if amount.zero?

      external_id = value.("transaction_id").presence
      return [:error, "transaction_id_too_long"] if external_id && external_id.length > MAX_TRANSACTION_ID

      # The optional balance is informational; an unreadable one is dropped, not an error.
      balance = value.("balance").empty? ? nil : parse_amount(value.("balance"))

      Row.new(line:, posted_on:, amount:, description:, external_id:, balance:)
    end

    def parse_date(text)
      year, month, day =
        if (m = ISO_DATE.match(text)) then [m[1], m[2], m[3]]
        elsif (m = US_DATE.match(text)) then [m[3], m[1], m[2]]
        end
      return nil if year.nil?

      Date.new(year.to_i, month.to_i, day.to_i)
    rescue Date::Error
      nil
    end

    def parse_amount(text)
      negative = false
      if text.start_with?("(") && text.end_with?(")")
        negative = true
        text = text[1..-2].strip
      end

      m = AMOUNT.match(text.delete(" "))
      return nil if m.nil?
      # One sign at most, and not combined with parentheses.
      return nil if m[:sign] && m[:sign2]
      return nil if negative && (m[:sign] || m[:sign2])

      negative ||= m[:sign] == "-" || m[:sign2] == "-"
      value = BigDecimal("#{m[:int].delete(',')}.#{m[:dec] || '0'}")
      negative ? -value : value
    end

    def file_error(code, message)
      Result.new(rows: [], errors: [], warnings: [], extra_columns: [],
                 file_error: FileError.new(code:, message:), has_transaction_id: false)
    end
  end
end
