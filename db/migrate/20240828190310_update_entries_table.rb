class UpdateEntriesTable < ActiveRecord::Migration[7.1]
  def change
     # Rename 'date' to 'start_date'
    rename_column :entries, :date, :start_date
    
    # Add 'frequency_number' and 'end_date'
    add_column :entries, :frequency_number, :integer
    add_column :entries, :end_date, :date
  end
end
