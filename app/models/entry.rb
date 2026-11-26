class Entry < ApplicationRecord
  belongs_to :budget
  belongs_to :category, optional: true
  has_and_belongs_to_many :tags

  validates :amount, numericality: true, allow_nil: true
end