class User < ApplicationRecord
  has_many :budgets, class_name: 'Budget', foreign_key: :user_id, dependent: :destroy
  has_many :entries_tags, dependent: :destroy 
  validates :first_name, :last_name, presence: true
  validates :email, presence: true, uniqueness: true
end
