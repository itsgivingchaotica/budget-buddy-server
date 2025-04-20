class AddBudgetIdToEntriesTags < ActiveRecord::Migration[7.1]
  def change
    # Add budget_id column
    add_column :entries_tags, :budget_id, :bigint

    # Add foreign key constraint to budgets table
    add_foreign_key :entries_tags, :budgets, column: :budget_id

    # Optionally, add an index for faster lookups
    add_index :entries_tags, :budget_id
  end
end
