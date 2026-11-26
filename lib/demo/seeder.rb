module Demo
  # DEMO-G (demo data generator): loads the generated files for a user
  # through the real import pipeline (CsvImport::Importer: parse, duplicate
  # detection, categorization), never by inserting rows directly.
  # Running it again imports nothing new (duplicates are detected).
  class Seeder
    # An in-memory upload, shaped like the file Rails hands the controller.
    class Upload < StringIO
      attr_reader :original_filename, :content_type

      def initialize(text, filename)
        super(text)
        @original_filename = filename
        @content_type = "text/csv"
      end
    end

    # The order a person would import them: three accounts, then a second
    # (overlapping) checking export, then the file with bad rows.
    PLAN = [
      ["checking", "checking.csv"], ["savings", "savings.csv"], ["venmo", "venmo.csv"],
      ["checking", "checking-overlap.csv"], ["checking", "malformed.csv"]
    ].freeze

    def self.call(user:, generator: Generator.new, log: ->(_line) {})
      new(user:, generator:, log:).call
    end

    def initialize(user:, generator:, log:)
      @user = user
      @generator = generator
      @log = log
    end

    # Returns [[filename, import, categorized_summary], ...].
    def call
      FinancialProfile.find_or_create_by!(user: @user)
      accounts = Generator::ACCOUNTS.to_h do |key, attrs|
        [key, @user.accounts.find_by(name: attrs[:name]) || @user.accounts.create!(attrs)]
      end
      files = @generator.files

      PLAN.map do |key, filename|
        import, _result, categorized = CsvImport::Importer.call(account: accounts[key], file: Upload.new(files[filename], filename))
        @log.call(format("%-22s %-18s inserted %4d, duplicates %4d, row errors %d, categorized %s",
                         filename, accounts[key].name, import.inserted_count, import.duplicate_count,
                         import.error_count, categorized.to_h))
        [filename, import, categorized]
      end
    end
  end
end
