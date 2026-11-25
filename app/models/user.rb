class User < ApplicationRecord
  has_many :budgets, class_name: 'Budget', foreign_key: :user_id, dependent: :destroy
  has_many :entries_tags, dependent: :destroy
  has_one :financial_profile, dependent: :destroy
  has_many :accounts, dependent: :destroy

  # Users created from a Kinde identity (S2) take names and email from Kinde,
  # which may not provide them; legacy users still need all three.
  validates :first_name, :last_name, presence: true, unless: :kinde_id?
  validates :email, presence: true, unless: :kinde_id?
  validates :email, uniqueness: { case_sensitive: false }, allow_nil: true
  validates :kinde_id, uniqueness: true, allow_nil: true

  def self.find_by_email_ci(email)
    return nil if email.blank?

    where("lower(email) = ?", email.to_s.strip.downcase).first
  end
end
