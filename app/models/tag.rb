class Tag < ApplicationRecord
  belongs_to :user
  belongs_to :category, optional: true
  has_and_belongs_to_many :entries
end