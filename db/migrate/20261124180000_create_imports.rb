# T1 (transactions tables), part 1: one row per CSV upload into one account
# (plan §2.2, §2.4). The uploaded file itself is never stored (AD13, Q-27):
# only counts, the filename and row errors as line number + error code.
# Owned through the account, so there is no user_id to drift. Additive and
# reversible.
class CreateImports < ActiveRecord::Migration[7.1]
  def change
    create_table :imports do |t|
      t.references :account, null: false, foreign_key: true
      t.string :filename, null: false
      t.string :status, null: false, default: "processing"
      t.integer :row_count, null: false, default: 0
      t.integer :inserted_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      # [{ "line": 7, "code": "bad_date" }, ...] - never raw row text.
      t.jsonb :row_errors, null: false, default: []
      t.date :data_from
      t.date :data_through

      t.timestamps
    end

    # Lets transactions point at (import, account) together, so a
    # transaction's import must belong to the same account (see next migration).
    add_index :imports, [:id, :account_id], unique: true

    add_check_constraint :imports, "status IN ('processing','completed','failed')", name: "imports_status_check"
    add_check_constraint :imports, "length(btrim(filename)) BETWEEN 1 AND 255", name: "imports_filename_length_check"
    add_check_constraint :imports,
                         "row_count >= 0 AND inserted_count >= 0 AND duplicate_count >= 0 AND error_count >= 0",
                         name: "imports_counts_check"
    add_check_constraint :imports, "jsonb_typeof(row_errors) = 'array'", name: "imports_row_errors_array_check"
    add_check_constraint :imports, "data_from IS NULL OR data_through IS NULL OR data_from <= data_through",
                         name: "imports_data_range_check"
  end
end
