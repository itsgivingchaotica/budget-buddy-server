# TR1 (transfer matching): a pair of the user's own transactions that look
# like one transfer between two accounts: money out of one, the same amount
# into another, at most 3 days apart. Suggested by TransferMatcher;
# confirming makes both rows Transfers (left out of spending and income);
# rejecting keeps the pair so it's never suggested again.
class TransferLink < ApplicationRecord
  STATUSES = %w[suggested confirmed rejected].freeze
  ACTIVE = %w[suggested confirmed].freeze
  MAX_DAYS_APART = 3

  belongs_to :user
  belongs_to :outflow_transaction, class_name: "Transaction"
  belongs_to :inflow_transaction, class_name: "Transaction"

  validates :status, inclusion: { in: STATUSES }
  validates :days_apart, numericality: { only_integer: true, in: 0..MAX_DAYS_APART }
  validate :rows_form_a_transfer

  scope :active, -> { where(status: ACTIVE) }

  # Links (any status) that include this transaction.
  def self.involving(transaction_id)
    where(outflow_transaction_id: transaction_id).or(where(inflow_transaction_id: transaction_id))
  end

  def transactions = [outflow_transaction, inflow_transaction]

  private

  def rows_form_a_transfer
    out, inn = outflow_transaction, inflow_transaction
    return if out.nil? || inn.nil?

    errors.add(:base, "both rows must belong to the user") unless [out, inn].all? { |t| t.account&.user_id == user_id }
    errors.add(:base, "rows must be in different accounts") if out.account_id == inn.account_id
    errors.add(:base, "outflow must be money out") unless out.amount.negative?
    errors.add(:base, "amounts must be equal and opposite") unless out.amount == -inn.amount
  end
end
