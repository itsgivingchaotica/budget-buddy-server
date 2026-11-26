# G1 (goals): money set aside for a saving goal, or a new balance for a debt.
# Undo = delete the row (SCREENS_PLAN §5). Owned through goal → user.
# Dated in the user's calendar (UserClock): today by default, never later.
class GoalContribution < ApplicationRecord
  KINDS = %w[set_aside balance_update].freeze

  belongs_to :goal

  normalizes :note, with: ->(note) { note.strip.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :contributed_on, presence: true
  validates :note, length: { maximum: 200 }, allow_nil: true
  validate :fields_for_kind
  validate :kind_fits_goal
  validate :not_in_the_future

  def set_aside? = kind == "set_aside"
  def balance_update? = kind == "balance_update"

  private

  def fields_for_kind
    if set_aside?
      errors.add(:amount, "must be greater than 0") unless amount&.positive? && amount <= Goal::MAX_AMOUNT
      errors.add(:balance_after, "is only for balance updates") unless balance_after.nil?
    elsif balance_update?
      errors.add(:balance_after, "must be 0 or more") unless balance_after && !balance_after.negative? && balance_after <= Goal::MAX_AMOUNT
      errors.add(:amount, "is only for set-asides") unless amount.nil?
    end
  end

  def kind_fits_goal
    return if goal.nil? || !KINDS.include?(kind)

    errors.add(:kind, "set_aside is for saving goals") if set_aside? && !goal.saving?
    errors.add(:kind, "balance_update is for debt goals") if balance_update? && !goal.debt?
  end

  def not_in_the_future
    return if goal.nil? || contributed_on.nil? || contributed_on <= UserClock.today(goal.user)

    errors.add(:contributed_on, "can't be in the future")
  end
end
