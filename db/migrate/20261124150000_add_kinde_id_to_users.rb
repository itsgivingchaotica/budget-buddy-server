# S2: link users to their Kinde identity (`sub`) and make emails unique
# regardless of case. Additive and reversible; no existing rows are changed.
class AddKindeIdToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :kinde_id, :string
    add_index :users, :kinde_id, unique: true
    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
  end
end
