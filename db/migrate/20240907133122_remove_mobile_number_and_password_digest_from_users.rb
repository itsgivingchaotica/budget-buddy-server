class RemoveMobileNumberAndPasswordDigestFromUsers < ActiveRecord::Migration[7.1]
  def change
    remove_column :users, :mobile_number, :string
    remove_column :users, :password_digest, :string
  end
end
