class CreateEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :entries do |t|
      t.references :budget, null: false, foreign_key: true
      t.string :entry_type
      t.date :date
      t.decimal :amount
      t.text :description
      t.string :frequency
      t.text :custom_frequency_days

      t.timestamps
    end
  end
end
