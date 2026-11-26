module Demo
  # DEMO-G (demo data generator): deletes one user's imported data so
  # demo:seed (or a re-import in the app) can load it again, e.g. after a
  # categorization change.
  #
  # Guards: runs only in development. By default it touches only the demo
  # account (demo.user@example.com); another account must be named
  # explicitly by email (USER_EMAIL=...), e.g. the developer's own login.
  # Deletes that user's transfer links (TR1), category corrections (C2b),
  # transactions, imports and merchant rules; keeps the user, accounts,
  # financial profile and AI usage rows (today's AI spend still counts
  # toward the cap).
  module Reset
    DEMO_EMAIL = "demo.user@example.com".freeze

    class Refused < StandardError; end

    module_function

    def call(env: Rails.env, email: DEMO_EMAIL)
      raise Refused, "demo:reset runs only in development (this is #{env})" unless env.to_s == "development"

      user = User.find_by_email_ci(email)
      if user.nil?
        raise Refused, "no user with that email" unless email == DEMO_EMAIL

        return { transfer_links: 0, category_corrections: 0, transactions: 0, imports: 0, merchant_rules: 0 }
      end

      account_ids = user.accounts.select(:id)
      ActiveRecord::Base.transaction do
        {
          transfer_links: TransferLink.where(user:).delete_all,
          category_corrections: CategoryCorrection.where(user:).delete_all,
          transactions: Transaction.where(account_id: account_ids).delete_all,
          imports: Import.where(account_id: account_ids).delete_all,
          merchant_rules: user.merchant_rules.delete_all
        }
      end
    end
  end
end
