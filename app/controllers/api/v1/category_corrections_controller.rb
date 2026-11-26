# C2b (review and transfer screens), handoff #05 §B.2: undo a category
# correction. Looked up through current_user.category_corrections, so
# another user's correction is a 404.
class Api::V1::CategoryCorrectionsController < ApplicationController
  before_action :require_current_user!

  # POST /category_corrections/:id/undo
  def undo
    correction = current_user.category_corrections.find(params[:id])
    restored = Categorization::Correction.undo(correction)
    render json: { restored_transaction_ids: restored, remaining: Categorization::Review.remaining(current_user) }
  rescue Categorization::Correction::AlreadyUndone
    render json: { error: "already_undone" }, status: :conflict
  end
end
