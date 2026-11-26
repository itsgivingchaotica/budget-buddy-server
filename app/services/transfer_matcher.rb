# TR1 (transfer matching): suggests pairs of the user's own transactions
# that are one transfer between two accounts (handoff #05 §A, PO-16):
#
#   - different accounts, amounts equal and opposite, dates <= 3 days apart;
#   - neither row already in a suggested or confirmed link, and the pair
#     never rejected before;
#   - when a row has several candidates: smallest date gap first, then the
#     earliest dates, then the lowest ids. Each row ends up in at most one
#     suggested or confirmed link.
#
# Deterministic and idempotent: candidate pairs are sorted by those keys and
# taken greedily; a second run finds nothing new. Runs after every import,
# over rows within +/- 3 days of the import's date range. Categorized rows
# are candidates too (e.g. a same-amount purchase near a repayment: the
# user rejects it).
class TransferMatcher
  def self.call(user:, from:, to:)
    new(user:, from:, to:).call
  end

  def initialize(user:, from:, to:)
    @user = user
    @from = from - TransferLink::MAX_DAYS_APART
    @to = to + TransferLink::MAX_DAYS_APART
  end

  # Returns the number of new suggested links.
  def call
    taken = TransferLink.where(user: @user).active.pluck(:outflow_transaction_id, :inflow_transaction_id).flatten.to_set
    rejected = TransferLink.where(user: @user, status: "rejected").pluck(:outflow_transaction_id, :inflow_transaction_id).to_set

    rows = @user.transactions.where(posted_on: @from..@to).where.not(id: taken.to_a)
                .pluck(:id, :account_id, :posted_on, :amount)
    outflows, inflows = rows.partition { |_, _, _, amount| amount.negative? }
    inflows_by_amount = inflows.group_by { |_, _, _, amount| amount }

    candidates = outflows.flat_map do |out_id, out_account, out_day, out_amount|
      Array(inflows_by_amount[-out_amount]).filter_map do |in_id, in_account, in_day, _|
        gap = (in_day - out_day).to_i.abs
        next if in_account == out_account || gap > TransferLink::MAX_DAYS_APART
        next if rejected.include?([out_id, in_id])

        [gap, [out_day, in_day].min, [out_day, in_day].max, out_id, in_id]
      end
    end

    used = Set.new
    created = 0
    candidates.sort.each do |gap, _, _, out_id, in_id|
      next if used.include?(out_id) || used.include?(in_id)

      used << out_id << in_id
      created += insert(out_id, in_id, gap)
    end
    created
  end

  private

  # INSERT ... ON CONFLICT DO NOTHING: a concurrent run can't create a
  # duplicate or a second active link for the same row.
  def insert(out_id, in_id, gap)
    now = Time.current
    TransferLink.insert_all(
      [{ user_id: @user.id, outflow_transaction_id: out_id, inflow_transaction_id: in_id, status: "suggested",
         days_apart: gap, created_at: now, updated_at: now }]
    ).length
  end
end
