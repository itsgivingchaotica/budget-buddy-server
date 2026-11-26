module Categorization
  # AI1 (rules-based categorization): stands in for the Claude step until
  # AI2 (Claude categorization). It never categorizes anything, so every row
  # memory and rules couldn't place goes to review.
  #
  # The interface AI2's client must keep:
  #   categorize(items:, allowed_slugs:) -> [{ index:, category_slug:, confidence: }]
  # where items are [{ index:, merchant:, amount:, account_purpose: }]:
  # the account's purpose (spending/bills/savings/side_income/other) lets AI2
  # suggest Income for money into a side-income account. No account names,
  # ids or user data are sent.
  class DisabledAi
    def categorize(items:, allowed_slugs:)
      []
    end
  end
end
