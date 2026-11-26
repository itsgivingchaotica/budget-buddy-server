# TR1 (transfer matching): suggested / confirmed / rejected pairs of the
# user's own transactions that are one transfer between two accounts
# (plan §2.2, handoff #05 §A). A link table rather than a column on
# transactions: it carries suggestion state, remembers rejections (so a
# pair is never suggested again) and holds the rows' previous state for
# Undo. Additive and reversible; foreign keys don't cascade.
class CreateTransferLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :transfer_links do |t|
      t.references :user, null: false, foreign_key: true
      t.references :outflow_transaction, null: false, foreign_key: { to_table: :transactions }, index: false
      t.references :inflow_transaction, null: false, foreign_key: { to_table: :transactions }, index: false
      t.string :status, null: false, default: "suggested"
      t.integer :days_apart, null: false
      # On confirm: each row's category_id, categorization_source,
      # confidence and needs_review before it became a Transfer (for Undo).
      t.jsonb :previous_state
      t.datetime :confirmed_at
      t.datetime :rejected_at

      t.timestamps
    end

    # A pair is stored once, whatever its status, so a rejected pair is
    # never suggested again.
    add_index :transfer_links, %i[outflow_transaction_id inflow_transaction_id], unique: true,
                                                                                    name: "index_transfer_links_on_pair"
    # A transaction is in at most one suggested or confirmed link.
    add_index :transfer_links, :outflow_transaction_id, unique: true, where: "status IN ('suggested','confirmed')",
                                                        name: "index_transfer_links_active_outflow"
    add_index :transfer_links, :inflow_transaction_id, unique: true, where: "status IN ('suggested','confirmed')",
                                                       name: "index_transfer_links_active_inflow"
    add_index :transfer_links, :inflow_transaction_id, name: "index_transfer_links_on_inflow"

    add_check_constraint :transfer_links, "status IN ('suggested','confirmed','rejected')", name: "transfer_links_status_check"
    add_check_constraint :transfer_links, "outflow_transaction_id <> inflow_transaction_id", name: "transfer_links_distinct_rows_check"
    add_check_constraint :transfer_links, "days_apart BETWEEN 0 AND 3", name: "transfer_links_days_apart_check"
  end
end
