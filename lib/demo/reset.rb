module Demo
  # DEMO-G (demo data generator): deletes the demo user's imported data so
  # demo:seed can load it again (e.g. after a categorization change).
  #
  # Guards: runs only in development, and only ever touches the fixed demo
  # account (demo.user@example.com). Deletes that user's transfer links (TR1),
  # transactions, imports and merchant rules; keeps the user, accounts, financial profile
  # and AI usage rows (so today's AI spend still counts toward the cap).
  module Reset
    DEMO_EMAIL = "demo.user@example.com".freeze

    class Refused < StandardError; end

    module_function

    def call(env: Rails.env)
      raise Refused, "demo:reset runs only in development (this is #{env})" unless env.to_s == "development"

      user = User.find_by(email: DEMO_EMAIL)
      return { transfer_links: 0, transactions: 0, imports: 0, merchant_rules: 0 } if user.nil?

      ActiveRecord::Base.transaction do
        {
          transfer_links: TransferLink.where(user:).delete_all,
          transactions: Transaction.where(account_id: user.accounts.select(:id)).delete_all,
          imports: Import.where(account_id: user.accounts.select(:id)).delete_all,
          merchant_rules: user.merchant_rules.delete_all
        }
      end
    end
  end
end
