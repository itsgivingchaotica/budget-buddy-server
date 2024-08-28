class Category < ApplicationRecord
  has_many :tags
  # Other associations and validations
end