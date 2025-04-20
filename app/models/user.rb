class User < ApplicationRecord
  has_many :budgets, :entries_tags, dependent: :destroy

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, uniqueness: true
end