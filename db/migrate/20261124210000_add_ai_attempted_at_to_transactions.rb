# AI2 (Claude categorization): remembers which uncategorized rows Claude has
# already answered (or the user cleared), so `POST /transactions/categorize`
# sends each row once, reports what's left, and resumes rows a failed call
# (429, network, daily cap) never reached. Nullable, no backfill: existing
# rows count as "not yet sent". Additive and reversible.
class AddAiAttemptedAtToTransactions < ActiveRecord::Migration[7.1]
  def change
    add_column :transactions, :ai_attempted_at, :datetime
    add_index :transactions, :account_id, where: "categorization_source = 'none' AND ai_attempted_at IS NULL",
                                          name: "index_transactions_awaiting_ai"
  end
end
