# DM-1: turn `categories` into one shared flat list (plan §2.2, §2.5).
#
# Additive and reversible. The 5 existing rows become kind = 'legacy',
# active = false through the column defaults applied when the columns are
# added (Postgres stores the default in its catalog: no UPDATE, no table
# rewrite). The `kind` default is then dropped so new rows must state their
# kind. Slugs and the new rows come from db/seeds.rb.
class AddFlatListColumnsToCategories < ActiveRecord::Migration[7.1]
  def change
    add_column :categories, :slug, :string
    add_column :categories, :kind, :string, null: false, default: "legacy"
    change_column_default :categories, :kind, from: "legacy", to: nil
    add_column :categories, :active, :boolean, null: false, default: false
    add_column :categories, :position, :integer
    add_column :categories, :need_want, :string
    add_column :categories, :fixed_variable, :string
    add_column :categories, :recurrence_label, :string

    add_index :categories, :slug, unique: true

    add_check_constraint :categories, "kind IN ('spending','income','transfer','legacy')",
                         name: "categories_kind_check"
    add_check_constraint :categories, "need_want IS NULL OR need_want IN ('need','want')",
                         name: "categories_need_want_check"
    add_check_constraint :categories, "fixed_variable IS NULL OR fixed_variable IN ('fixed','variable')",
                         name: "categories_fixed_variable_check"
    add_check_constraint :categories, "recurrence_label IS NULL OR recurrence_label IN ('one_time','recurring')",
                         name: "categories_recurrence_label_check"
    add_check_constraint :categories, "kind <> 'spending' OR fixed_variable IS NOT NULL",
                         name: "categories_spending_needs_fixed_variable"
    add_check_constraint :categories, "kind = 'legacy' OR slug IS NOT NULL",
                         name: "categories_slug_required"
  end
end
