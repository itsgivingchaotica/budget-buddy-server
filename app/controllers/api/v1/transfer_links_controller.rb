# TR1 (transfer matching): the caller's suggested / confirmed / rejected
# transfer pairs (handoff #05 §A). Every lookup goes through
# current_user.transfer_links, so another user's link is a 404. Confirm is
# the only way a transaction gets the Transfers category.
class Api::V1::TransferLinksController < ApplicationController
  include MoneyJson

  before_action :require_current_user!
  before_action :set_link, except: :index

  # GET /transfer_links?status=suggested (default suggested)
  def index
    status = params.fetch(:status, "suggested").to_s
    return render json: { error: "invalid_parameter", field: "status" }, status: :unprocessable_entity unless TransferLink::STATUSES.include?(status)

    links = current_user.transfer_links.where(status:)
                        .includes(outflow_transaction: :account, inflow_transaction: :account)
                        .order(:id)
    render json: { transfer_links: links.map { |link| link_json(link) }, total: links.size }
  end

  # POST /transfer_links/:id/confirm - both rows become Transfers (left out of
  # spending and income); their previous state is kept on the link for Undo.
  def confirm
    transfers = Category.active_list.find_by(kind: "transfer")
    return render json: { error: "transfers_category_missing" }, status: :unprocessable_entity if transfers.nil?

    @link.with_lock do
      return render_state_conflict unless @link.status == "suggested"

      rows = @link.transactions
      previous = rows.to_h do |t|
        [t.id.to_s, t.slice(:category_id, :categorization_source, :needs_review, :suggested_category_id)
                     .merge("confidence" => t.confidence&.to_s)]
      end
      rows.each do |t|
        t.update!(category: transfers, categorization_source: "transfer", confidence: nil, needs_review: false)
      end
      @link.update!(status: "confirmed", confirmed_at: Time.current, previous_state: previous)
    end
    render json: link_json(@link.reload)
  end

  # POST /transfer_links/:id/reject - kept, so the pair is never suggested
  # again; the rows stay as they are (in review).
  def reject
    @link.with_lock do
      return render_state_conflict unless @link.status == "suggested"

      @link.update!(status: "rejected", rejected_at: Time.current)
    end
    render json: link_json(@link.reload)
  end

  # DELETE /transfer_links/:id - Undo. Confirmed: restore both rows (only if
  # they're still Transfers from this confirm) and go back to suggested.
  # Rejected: back to suggested.
  def destroy
    @link.with_lock do
      case @link.status
      when "confirmed"
        @link.transactions.each do |t|
          before = @link.previous_state&.dig(t.id.to_s)
          next if before.nil? || t.categorization_source != "transfer"

          t.update!(category_id: before["category_id"], categorization_source: before["categorization_source"],
                    needs_review: before["needs_review"], confidence: before["confidence"],
                    suggested_category_id: before["suggested_category_id"])
        end
        @link.update!(status: "suggested", confirmed_at: nil, previous_state: nil)
      when "rejected"
        @link.update!(status: "suggested", rejected_at: nil)
      else
        return render json: { error: "nothing_to_undo" }, status: :conflict
      end
    end
    render json: link_json(@link.reload)
  rescue ActiveRecord::RecordNotUnique
    # Since the rejection, one of the rows joined another transfer pair.
    render json: { error: "row_in_another_transfer" }, status: :conflict
  end

  private

  def set_link
    @link = current_user.transfer_links.find(params[:id])
  end

  def render_state_conflict
    render json: { error: "not_suggested", status: @link.status }, status: :conflict
  end

  def link_json(link)
    {
      id: link.id, status: link.status, days_apart: link.days_apart,
      amount: money(link.outflow_transaction.amount.abs),
      outflow: side_json(link.outflow_transaction), inflow: side_json(link.inflow_transaction)
    }
  end

  def side_json(t)
    { id: t.id, account_id: t.account_id, account_name: t.account.name, posted_on: t.posted_on,
      description: t.description, amount: money(t.amount) }
  end
end
