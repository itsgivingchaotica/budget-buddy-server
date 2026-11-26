# One per user (plan §2.2). Typed columns are what calculations read;
# free-form onboarding answers live in `answers`.
#
# week_starts_on: the first day of the user's week, as Ruby's Date#wday
#   (0 = Sunday, 1 = Monday, ... 6 = Saturday). Default 1 = Monday (PO-12).
# time_zone: an IANA zone name (e.g. "Europe/London"), nil until set (PO-12).
class FinancialProfile < ApplicationRecord
  MONDAY = 1
  SUNDAY = 0

  PAY_FREQUENCIES = %w[weekly biweekly semimonthly monthly irregular].freeze
  CHANGE_APPETITES = %w[small medium large].freeze

  belongs_to :user

  validates :user_id, uniqueness: true
  validates :week_starts_on, inclusion: { in: 0..6 }
  validates :pay_frequency, inclusion: { in: PAY_FREQUENCIES }, allow_nil: true
  validates :change_appetite, inclusion: { in: CHANGE_APPETITES }, allow_nil: true
  validates :typical_pay_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :time_zone_is_iana, if: -> { time_zone.present? }

  def self.valid_time_zone?(name)
    name.is_a?(String) && name.length <= 64 && TZInfo::Timezone.get(name).present?
  rescue TZInfo::InvalidTimezoneIdentifier
    false
  end

  def onboarding_completed?
    onboarding_completed_at.present?
  end

  private

  def time_zone_is_iana
    errors.add(:time_zone, "is not a valid IANA time zone") unless self.class.valid_time_zone?(time_zone)
  end
end
