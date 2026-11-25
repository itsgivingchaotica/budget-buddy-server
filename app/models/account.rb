# DM-2 (accounts): one of the user's money accounts. Owned directly by the
# user; imports and transactions (T1) are reached through it, so ownership
# can't drift. "Deleting" archives: the row and its history stay.
#
# Amount sign convention for everything imported into an account: money out
# of the account is negative, money in is positive. For a credit card,
# purchases are negative and payments to the card positive (PO-17).
class Account < ApplicationRecord
  KINDS = %w[checking savings credit_card p2p cash other].freeze
  PURPOSES = %w[spending bills savings side_income other].freeze

  belongs_to :user

  normalizes :name, with: ->(name) { name.strip }
  normalizes :purpose_note, with: ->(note) { note.strip.presence }

  validates :name, presence: true, length: { maximum: 60 },
                   uniqueness: { scope: :user_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :purpose, inclusion: { in: PURPOSES }
  validates :purpose_note, length: { maximum: 200 }, allow_nil: true

  scope :active, -> { where(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current) unless archived?
  end
end
