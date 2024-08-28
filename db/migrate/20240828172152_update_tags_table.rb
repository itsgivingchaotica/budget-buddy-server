class UpdateTagsTable < ActiveRecord::Migration[7.1]
  def change
    remove_column :tags, :tag_type, :string
  end
end
