# AI1 (rules-based categorization): merchant memory. One row per user and
# merchant: "this merchant is this category". AI1 reads it before keyword
# rules or any AI; AI3 (learning from corrections) writes it when the user
# recategorizes a transaction. Points at categories, not tags (plan §2.2).
# Additive and reversible; foreign keys don't cascade.
class CreateMerchantRules < ActiveRecord::Migration[7.1]
  def change
    create_table :merchant_rules do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :merchant_key, null: false
      t.references :category, null: false, foreign_key: true
      t.integer :hits, null: false, default: 0
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :merchant_rules, [:user_id, :merchant_key], unique: true
    add_check_constraint :merchant_rules, "length(merchant_key) BETWEEN 1 AND 255", name: "merchant_rules_key_length_check"
    add_check_constraint :merchant_rules, "hits >= 0", name: "merchant_rules_hits_check"
  end
end
