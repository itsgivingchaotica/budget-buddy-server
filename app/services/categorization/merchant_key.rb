module Categorization
  # AI1 (rules-based categorization): the merchant a transaction is from,
  # used by merchant memory and keyword rules. Starts from the transaction's
  # normalized description (upper case, store numbers and card digits already
  # stripped, T1) and also drops card-processor prefixes, so "SQ *BLUE
  # BOTTLE" and "BLUE BOTTLE" are the same merchant.
  module MerchantKey
    PREFIXES = [
      /\A(?:SQ|SQU|TST|SP|PY|DD|IN|PP|PAYPAL)\s?\*\s*/, # card processors: "SQ *", "TST* ", "PAYPAL *"
      /\A(?:POS|ACH|DEBIT|CHECKCARD|PURCHASE|RECURRING)\s+(?:PURCHASE\s+|DEBIT\s+|PAYMENT\s+)?/,
      /\A(?:DEBIT CARD PURCHASE|CARD PURCHASE|ONLINE PAYMENT TO)\s+/
    ].freeze

    def self.for(normalized_description)
      key = normalized_description.to_s.upcase.strip
      loop do
        stripped = PREFIXES.reduce(key) { |k, pattern| k.sub(pattern, "") }.strip
        break if stripped == key || stripped.empty?

        key = stripped
      end
      key[0, 255]
    end
  end
end
