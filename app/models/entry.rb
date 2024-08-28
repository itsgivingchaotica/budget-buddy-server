class Entry < ApplicationRecord
  belongs_to :budget
  has_and_belongs_to_many :tags
end