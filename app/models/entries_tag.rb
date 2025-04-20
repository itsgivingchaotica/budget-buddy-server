class EntriesTag < ApplicationRecord
  belongs_to :entry
  belongs_to :tag
  belongs_to :user
end