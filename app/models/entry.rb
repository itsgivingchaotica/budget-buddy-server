class Entry < ApplicationRecord
  belongs_to :budget
  belongs_to :category
  has_and_belongs_to_many :tags
end