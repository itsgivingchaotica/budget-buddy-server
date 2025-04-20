class AddUserIdToEntriesTags < ActiveRecord::Migration[7.1]
  def change
    add_column :entries_tags, :user_id, :bigint
    add_foreign_key :entries_tags, :users, column: :user_id
    add_index :entries_tags, :user_id # Optional, to add an index for faster lookups
  end
end