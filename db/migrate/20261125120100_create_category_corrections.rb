# C2b (review and transfer screens), handoff #05 §B.2: each category
# correction (PATCH /transactions/:id with a category) is recorded with the
# previous state of every row it changed and of the merchant rule, so
# POST /category_corrections/:id/undo can put things back exactly.
# Additive and reversible; foreign keys don't cascade.
class CreateCategoryCorrections < ActiveRecord::Migration[7.1]
  def change
    create_table :category_corrections do |t|
      t.references :user, null: false, foreign_key: true
      t.references :transaction, null: false, foreign_key: true # the row the user picked
      t.references :new_category, null: false, foreign_key: { to_table: :categories }
      t.string :merchant_key, null: false
      # [{ "id", "category_id", "categorization_source", "confidence",
      #    "needs_review", "suggested_category_id" }, ...] for every changed row.
      t.jsonb :previous, null: false, default: []
      # The merchant rule before the correction ({ "category_id", "hits",
      # "last_used_at" }), or null if the correction created it.
      t.jsonb :merchant_rule_before
      t.datetime :undone_at

      t.timestamps
    end

    add_check_constraint :category_corrections, "jsonb_typeof(previous) = 'array'", name: "category_corrections_previous_array_check"
  end
end
