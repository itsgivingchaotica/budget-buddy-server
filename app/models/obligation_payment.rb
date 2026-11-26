# OB1 (bills), plan §2.2 / spec §8.1: one paid occurrence of a bill. A row
# exists = that occurrence (obligation + due date) is paid; "mark unpaid"
# deletes it. Owned through obligation → user.
class ObligationPayment < ApplicationRecord
  belongs_to :obligation

  validates :due_on, :paid_on, presence: true
  validates :due_on, uniqueness: { scope: :obligation_id }
  validate :due_on_is_an_occurrence
  validate :paid_on_not_in_the_future

  private

  def due_on_is_an_occurrence
    return if obligation.nil? || due_on.nil? || obligation.schedule.occurs_on?(due_on)

    errors.add(:due_on, "isn't a due date of this bill")
  end

  # "Today" in the user's zone (UserClock); paying early is fine.
  def paid_on_not_in_the_future
    return if obligation.nil? || paid_on.nil? || paid_on <= UserClock.today(obligation.user)

    errors.add(:paid_on, "can't be in the future")
  end
end
