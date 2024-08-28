class AddDefaultTagToTags < ActiveRecord::Migration[7.1]
  def change
    add_column :tags, :default_tag, :boolean, default: false
  end
end
