# DM-3 (category budgets), plan §2.2: a monthly budget per flexible
# category. A row applies from its month (effective_from, always the 1st)
# until a later row replaces it, so there are no per-month copies; the
# amount a month uses is the row in effect on that month's 1st. Additive and
# reversible; foreign keys don't cascade. plan_proposal_id arrives with PL1.
class CreateCategoryBudgets < ActiveRecord::Migration[7.1]
  def change
    create_table :category_budgets do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :category, null: false, foreign_key: true
      t.string :period, null: false, default: "month"
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.date :effective_from, null: false
      t.string :source, null: false, default: "user"

      t.timestamps
    end

    add_index :category_budgets, %i[user_id category_id effective_from], unique: true,
                                                                          name: "index_category_budgets_on_user_category_month"
    add_check_constraint :category_budgets, "period = 'month'", name: "category_budgets_period_check"
    add_check_constraint :category_budgets, "amount >= 0", name: "category_budgets_amount_check"
    add_check_constraint :category_budgets, "EXTRACT(DAY FROM effective_from) = 1", name: "category_budgets_first_of_month_check"
    add_check_constraint :category_budgets, "source IN ('user','coach')", name: "category_budgets_source_check"
  end
end
