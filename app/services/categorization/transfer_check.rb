module Categorization
  # AI2 (Claude categorization): a deterministic check for money moved
  # between the user's own accounts. Such rows can't be categorized (only
  # TR1, transfer matching, sets Transfers), so they go straight to review
  # with source "none" and are never sent to Claude (PO, 2026-11-25).
  #
  # Transfer-like: "TRANSFER TO/FROM", "CASH OUT"/"CASHOUT", or the name of
  # another of the user's own accounts (whole words, names of 4+ characters).
  # Person-to-person payments (Zelle, Venmo "Payment to/from") and
  # marketplaces (Amazon) are not transfer-like: they still go to Claude.
  module TransferCheck
    PATTERNS = [
      /(?:\A|[^A-Z0-9])TRANSFER\s+(?:TO|FROM)(?:[^A-Z0-9]|\z)/,
      /(?:\A|[^A-Z0-9])CASH\s?OUT(?:[^A-Z0-9]|\z)/
    ].freeze
    MIN_ACCOUNT_NAME = 4

    module_function

    # other_account_names: the user's account names, except the row's own.
    def transfer_like?(merchant_key, other_account_names = [])
      key = merchant_key.to_s.upcase
      return true if PATTERNS.any? { |p| p.match?(key) }

      other_account_names.any? do |name|
        name = name.to_s.upcase.gsub(/\s+/, " ").strip
        name.length >= MIN_ACCOUNT_NAME && key.match?(/(?:\A|[^A-Z0-9])#{Regexp.escape(name)}(?:[^A-Z0-9]|\z)/)
      end
    end
  end
end
