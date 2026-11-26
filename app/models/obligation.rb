# OB1 (bills), plan §2.2: a bill with a structured schedule (RecurrenceSchedule).
# Owned directly by the user. Only fixed spending categories (Rent,
# Utilities, Subscriptions, Insurance, Debt Payments, Education; spec §7):
# flexible categories have budgets instead. The optional account is the one
# it's paid from and must be the same user's. "Deleting" archives: the row
# and its payments stay.
class Obligation < ApplicationRecord
  SOURCES = %w[interview user coach].freeze
  MAX_AMOUNT = BigDecimal("9999999999.99")

  belongs_to :user
  belongs_to :category
  belongs_to :account, optional: true
  has_many :payments, class_name: "ObligationPayment", dependent: :restrict_with_exception

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 80 }
  validates :amount, numericality: { greater_than: 0, less_than_or_equal_to: MAX_AMOUNT }
  validates :first_due_on, presence: true
  validates :recurrence, inclusion: { in: RecurrenceSchedule::KINDS }
  validates :interval, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 52 }
  validates :day_of_month, numericality: { only_integer: true, in: 1..31 }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }
  validate :category_is_fixed
  validate :account_is_the_users
  validate :schedule_is_consistent
  validate :ends_after_it_starts

  before_validation :set_day_of_month

  scope :active, -> { where(archived_at: nil) }

  def archived? = archived_at.present?

  def archive!
    update_columns(archived_at: Time.current, updated_at: Time.current) unless archived?
  end

  def schedule = RecurrenceSchedule.for(self)

  private

  # Monthly/yearly bills keep their day (default: first_due_on's day); other
  # schedules have none.
  def set_day_of_month
    if RecurrenceSchedule::MONTHLY.include?(recurrence)
      self.day_of_month ||= first_due_on&.day
    else
      self.day_of_month = nil
    end
  end

  def category_is_fixed
    return if category.nil? || Category.fixed.exists?(category.id)

    errors.add(:category, "must be a fixed spending category (flexible categories have budgets)")
  end

  def account_is_the_users
    errors.add(:account, "must be one of your accounts") if account && account.user_id != user_id
  end

  def schedule_is_consistent
    return if first_due_on.nil? || errors.include?(:recurrence) || errors.include?(:interval) || errors.include?(:day_of_month)
    return if schedule.consistent?

    errors.add(:first_due_on, "must fall on day #{day_of_month} (or the month's last day when shorter)")
  end

  def ends_after_it_starts
    errors.add(:ends_on, "must be on or after the first due date") if ends_on && first_due_on && ends_on < first_due_on
  end
end
