# G1 (goals), plan §2.2, D-013: one table for the three goal types.
#
#   upcoming_payment  a target amount by a date (e.g. car insurance)
#   purchase          a target amount, date optional (e.g. an emergency fund, PO-4)
#   debt_payoff       a starting balance, APR and monthly payment (D-011)
#
# Progress is computed from goal_contributions, never stored (PO, 2026-11-26):
#   saved   = starting_balance + set-asides               (saving goals)
#   balance = latest balance update, else starting_balance (debt)
# "Deleting" archives (status archived): the row and its contributions stay.
class Goal < ApplicationRecord
  TYPES = %w[upcoming_payment purchase debt_payoff].freeze
  SAVING_TYPES = %w[upcoming_payment purchase].freeze
  STATUSES = %w[active completed archived].freeze
  SOURCES = %w[interview user coach].freeze
  MAX_AMOUNT = BigDecimal("9999999999.99")

  belongs_to :user
  has_many :contributions, class_name: "GoalContribution", dependent: :restrict_with_exception

  normalizes :name, with: ->(name) { name.strip }

  validates :goal_type, inclusion: { in: TYPES }
  validates :name, presence: true, length: { maximum: 80 }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :starting_balance, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_AMOUNT }
  validate :type_fields

  scope :active, -> { where(status: "active") }

  def saving? = SAVING_TYPES.include?(goal_type)
  def debt? = goal_type == "debt_payoff"

  # Saving goals: starting amount plus every set-aside.
  def saved
    return nil unless saving?

    starting_balance + contributions.select(&:set_aside?).sum(BigDecimal("0"), &:amount)
  end

  # Debt: the latest balance update (by date, then entry order), else the starting balance.
  def balance
    return nil unless debt?

    latest = contributions.select(&:balance_update?).max_by { |c| [c.contributed_on, c.id] }
    latest ? latest.balance_after : starting_balance
  end

  # What's still to save or pay (never below 0).
  def remaining
    value = saving? ? target_amount - saved : balance
    [value, BigDecimal("0")].max
  end

  private

  def type_fields
    if saving?
      positive(:target_amount)
      errors.add(:target_date, "is required for an upcoming payment") if goal_type == "upcoming_payment" && target_date.nil?
      %i[apr monthly_payment].each { |f| errors.add(f, "is only for debt goals") unless self[f].nil? }
    elsif debt?
      errors.add(:starting_balance, "must be greater than 0 for a debt") unless starting_balance.to_d.positive?
      positive(:monthly_payment)
      errors.add(:apr, "must be between 0 and 100") unless apr && apr.between?(0, 100)
      %i[target_amount target_date].each { |f| errors.add(f, "isn't used for debt goals") unless self[f].nil? }
    end
  end

  def positive(field)
    value = self[field]
    errors.add(field, "must be greater than 0") unless value && value.positive? && value <= MAX_AMOUNT
  end
end
