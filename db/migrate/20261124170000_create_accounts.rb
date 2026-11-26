# DM-2 (accounts): the user's checking, savings, credit card, Venmo... accounts.
# Every imported transaction will belong to an account (T1), and accounts are
# never hard-deleted (archived_at), so their history is kept. Additive and
# reversible.
class CreateAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.string :purpose, null: false
      t.string :purpose_note
      # Balance-based "safe to spend" is v1 (PO-6); kept optional, set as a pair.
      t.decimal :opening_balance, precision: 12, scale: 2
      t.date :opening_balance_on
      t.datetime :archived_at

      t.timestamps
    end

    add_index :accounts, "user_id, lower(name)", unique: true, name: "index_accounts_on_user_id_and_lower_name"

    add_check_constraint :accounts, "kind IN ('checking','savings','credit_card','p2p','cash','other')",
                         name: "accounts_kind_check"
    add_check_constraint :accounts, "purpose IN ('spending','bills','savings','side_income','other')",
                         name: "accounts_purpose_check"
    add_check_constraint :accounts, "length(btrim(name)) BETWEEN 1 AND 60", name: "accounts_name_length_check"
    add_check_constraint :accounts, "(opening_balance IS NULL) = (opening_balance_on IS NULL)",
                         name: "accounts_opening_balance_pair_check"
  end
end
