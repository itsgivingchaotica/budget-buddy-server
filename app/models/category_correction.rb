# C2b (review and transfer screens), handoff #05 §B.2: one category
# correction (a user's pick on Review or PATCH /transactions/:id), with the
# previous state of every row it changed and of the merchant rule, so it can
# be undone exactly. Owned directly by the user.
class CategoryCorrection < ApplicationRecord
  belongs_to :user
  # The column is transaction_id (as specified); `transaction` is a Rails
  # method, so the association has another name.
  belongs_to :picked_transaction, class_name: "Transaction", foreign_key: :transaction_id, inverse_of: :category_corrections
  belongs_to :new_category, class_name: "Category"

  validates :merchant_key, presence: true
  validate :previous_is_a_list

  def undone? = undone_at.present?

  private

  def previous_is_a_list
    errors.add(:previous, "must be a list") unless previous.is_a?(Array)
  end
end
