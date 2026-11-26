# T1 (transactions tables), part 2: bank movements, owned through accounts
# (plan §2.2, D-007). Legacy `entries` are not reused: they are planned,
# budget-owned lines.
#
# Sign convention (§2.4, PO-17): negative = money out of the account,
# positive = money in. Zero amounts are skipped at import, so never stored.
#
# Duplicate keys (§2.3):
#   base_key   = SHA-256(posted_on | amount_cents | normalized_description),
#                unique per account together with `occurrence` (the Nth
#                identical row in a file).
#   external_id = the bank's transaction id when the CSV has one; unique per
#                account where present.
#
# Foreign keys don't cascade: accounts are archived, never deleted. Additive
# and reversible.
class CreateTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :transactions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :import, foreign_key: false # composite FK below
      t.date :posted_on, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :description, null: false
      t.string :normalized_description, null: false
      t.string :external_id
      t.string :base_key, null: false
      t.integer :occurrence, null: false, default: 1
      t.references :category, foreign_key: true
      t.string :categorization_source, null: false, default: "none"
      t.decimal :confidence, precision: 4, scale: 3
      t.boolean :needs_review, null: false, default: false

      t.timestamps
    end

    add_index :transactions, [:account_id, :base_key, :occurrence], unique: true,
                                                                     name: "index_transactions_on_account_base_key_occurrence"
    add_index :transactions, [:account_id, :external_id], unique: true, where: "external_id IS NOT NULL",
                                                           name: "index_transactions_on_account_external_id"
    add_index :transactions, [:account_id, :posted_on]

    # The import (when there is one) must be an import into the same account.
    # MATCH SIMPLE: rows with no import_id (manual/cash) aren't checked.
    add_foreign_key :transactions, :imports, column: [:import_id, :account_id], primary_key: [:id, :account_id],
                                             name: "fk_transactions_import_same_account"

    add_check_constraint :transactions, "amount <> 0", name: "transactions_amount_nonzero_check"
    add_check_constraint :transactions, "length(btrim(description)) BETWEEN 1 AND 255",
                         name: "transactions_description_length_check"
    add_check_constraint :transactions, "length(normalized_description) BETWEEN 1 AND 255",
                         name: "transactions_normalized_description_length_check"
    add_check_constraint :transactions, "base_key ~ '^[0-9a-f]{64}$'", name: "transactions_base_key_format_check"
    add_check_constraint :transactions, "occurrence >= 1", name: "transactions_occurrence_check"
    add_check_constraint :transactions, "external_id IS NULL OR length(btrim(external_id)) BETWEEN 1 AND 255",
                         name: "transactions_external_id_length_check"
    add_check_constraint :transactions,
                         "categorization_source IN ('user','memory','rule','ai','transfer','none')",
                         name: "transactions_categorization_source_check"
    # "none" means uncategorized; every other source means a category was set.
    add_check_constraint :transactions, "(categorization_source = 'none') = (category_id IS NULL)",
                         name: "transactions_source_matches_category_check"
    add_check_constraint :transactions, "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)",
                         name: "transactions_confidence_range_check"
  end
end
