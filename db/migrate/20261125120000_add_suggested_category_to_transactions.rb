# C2b (review and transfer screens), handoff #05 §B.1: Claude's
# below-threshold guess for a row waiting for review, shown as the "?" chip.
# It never counts as categorized, and a row never has both a category and a
# suggestion. Nullable, no backfill. Additive and reversible.
class AddSuggestedCategoryToTransactions < ActiveRecord::Migration[7.1]
  def change
    add_reference :transactions, :suggested_category, foreign_key: { to_table: :categories }
    add_check_constraint :transactions, "suggested_category_id IS NULL OR category_id IS NULL",
                         name: "transactions_suggestion_only_when_uncategorized_check"
  end
end
