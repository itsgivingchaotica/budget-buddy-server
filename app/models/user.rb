class User < ApplicationRecord
  has_secure_password  # Adds methods to set and authenticate against a BCrypt password

  has_many :budgets, dependent: :destroy

  validates :first_name, :last_name, presence: true
  validates :email, uniqueness: true, if: -> { email.present? }
  validate :email_or_mobile_number_present

  private

  def email_or_mobile_number_present
    if email.blank? && mobile_number.blank?
      errors.add(:base, "Either email or mobile number must be present")
    end
  end
end