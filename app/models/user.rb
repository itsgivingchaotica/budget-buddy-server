class User < ApplicationRecord
  has_many :budgets, dependent: :destroy

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, uniqueness: true
end