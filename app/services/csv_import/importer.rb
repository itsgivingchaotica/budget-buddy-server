module CsvImport
  # I2 (import endpoint): imports one uploaded CSV into one of the caller's
  # accounts. The file is read in memory, parsed by CsvImport::Parser (I1)
  # and discarded; only the `imports` row (counts, filename, { line, code }
  # errors) and the new transactions are stored (AD13, Q-27).
  #
  # Duplicate detection (plan §2.3):
  #   - Rows with a bank transaction_id are keyed on it (occurrence 1).
  #   - Other rows are keyed on SHA-256(date | cents | normalized
  #     description), and identical rows within the file are numbered
  #     1, 2, 3... (`occurrence`), so re-importing the same file, or the same
  #     rows in a different order, inserts nothing, while two genuine
  #     identical purchases on one day are both kept.
  #   - Inserted with INSERT ... ON CONFLICT DO NOTHING, so an existing row
  #     is counted as a duplicate instead of failing the import.
  # Known limits (accepted in §2.3): a pending -> posted description change,
  # and overlapping files with different counts of identical rows.
  class Importer
    ALLOWED_CONTENT_TYPES = %w[
      text/csv text/plain application/csv text/comma-separated-values
      application/vnd.ms-excel application/octet-stream
    ].freeze
    BATCH_SIZE = 1_000

    class Rejected < StandardError
      attr_reader :code

      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    def self.call(account:, file:)
      new(account:, file:).call
    end

    def initialize(account:, file:)
      @account = account
      @file = file
    end

    # Returns [import, parse_result, categorization_summary]; raises Rejected for a file that can't
    # be imported at all (nothing is stored then).
    def call
      check_account_and_file!
      result = Parser.parse(read_file)
      raise Rejected.new(result.file_error.code, result.file_error.message) unless result.ok?

      import = nil
      ActiveRecord::Base.transaction do
        import = @account.imports.create!(filename:, status: "processing")
        inserted = insert_rows(import, result.rows)
        dates = result.rows.map(&:posted_on)
        import.update!(
          status: "completed",
          row_count: result.rows.size + result.errors.size + result.warnings.size,
          inserted_count: inserted,
          duplicate_count: result.rows.size - inserted,
          error_count: result.errors.size,
          row_errors: result.errors,
          data_from: dates.min,
          data_through: dates.max
        )
      end
      # AI1 (rules-based categorization), after the import is saved, so a
      # categorization problem never loses imported rows.
      categorized = Categorization::Pipeline.call(user: @account.user, scope: import.transactions)
      [import, result, categorized]
    end

    private

    def check_account_and_file!
      raise Rejected.new("account_archived", "This account is archived.") if @account.archived?
      unless @file.respond_to?(:read) && @file.respond_to?(:original_filename)
        raise Rejected.new("file_missing", "Attach a CSV file as `file`.")
      end
      unless File.extname(@file.original_filename.to_s).casecmp?(".csv") &&
             ALLOWED_CONTENT_TYPES.include?(@file.content_type.to_s.split(";").first.to_s.strip.downcase)
        raise Rejected.new("wrong_file_type", "Upload a .csv file.")
      end
      return unless @file.size > Parser::MAX_BYTES

      raise Rejected.new("file_too_large", "The file is over 2 MB.")
    end

    def read_file
      @file.rewind if @file.respond_to?(:rewind)
      @file.read
    end

    def filename
      name = File.basename(@file.original_filename.to_s).strip
      name = "upload.csv" if name.empty?
      name[0, 255]
    end

    def insert_rows(import, rows)
      now = Time.current
      seen = Hash.new(0)
      records = rows.map do |row|
        normalized = Transaction.normalize_description(row.description)
        key = Transaction.duplicate_key_for(posted_on: row.posted_on, amount: row.amount,
                                            normalized_description: normalized, external_id: row.external_id)
        occurrence = row.external_id ? 1 : (seen[key] += 1)
        {
          account_id: @account.id, import_id: import.id, posted_on: row.posted_on, amount: row.amount,
          description: row.description, normalized_description: normalized, external_id: row.external_id,
          base_key: key, occurrence:, categorization_source: "none", needs_review: false,
          created_at: now, updated_at: now
        }
      end

      records.each_slice(BATCH_SIZE).sum do |batch|
        Transaction.insert_all(batch, returning: [:id]).length
      end
    end
  end
end
