class UpdateEntryTypeToCategoryIdInEntries < ActiveRecord::Migration[7.1]
  def change
    remove_column :entries, :entry_type, :string
    add_reference :entries, :category, foreign_key: true
  end
end
