class AddCategoryIdToTags < ActiveRecord::Migration[7.1]
  def change
    add_reference :tags, :category, foreign_key: true
  end
end
