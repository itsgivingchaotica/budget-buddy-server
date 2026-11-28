# PL1 (plan drafting), SPEC_ONBOARDING_PLAN §6.4 and §7 (adjustments), D-032:
# the caller's own draft plan. Every figure is Rails'; money as strings.
#
#   POST  /plan_proposals          build a new draft (supersedes the open one);
#                                  at most 5 a day (429); the AI cap or an
#                                  outage gives the fallback draft, never an error
#   GET   /plan_proposals/current  the open draft, else the latest approved plan,
#                                  else { plan_proposal: null }
#   PATCH /plan_proposals/:id      adjust a draft (budgets, bills, goals); 409 if
#                                  it isn't a draft, 422 if stale or invalid
# Another user's proposal → 404 (S3). Approval is PL2.
class Api::V1::PlanProposalsController < ApplicationController
  before_action :require_current_user!

  def create
    AiRateLimit.hit!(current_user, :plan)
    render json: { plan_proposal: json(PlanDrafter.call(current_user)) }, status: :created
  rescue AiRateLimit::Limited => e
    response.set_header("Retry-After", e.retry_after.to_s)
    render json: { error: "rate_limited", retry_after: e.retry_after }, status: :too_many_requests
  end

  def current
    proposals = current_user.plan_proposals
    proposal = proposals.drafts.order(:id).last || proposals.where(status: "approved").order(:approved_at, :id).last
    render json: { plan_proposal: proposal && json(proposal) }
  end

  def update
    proposal = current_user.plan_proposals.find(params[:id])
    return render json: { error: "not_a_draft", status: proposal.status }, status: :conflict unless proposal.status == "draft"
    return render json: { error: "stale" }, status: :unprocessable_entity if proposal.stale?

    changes = params.permit!.to_h.slice("budgets", "bills", "goals")
    render json: { plan_proposal: json(PlanEdits.apply!(proposal, changes)) }
  rescue PlanEdits::Invalid => e
    render json: { error: "invalid", errors: e.errors }, status: :unprocessable_entity
  end

  private

  def json(proposal)
    proposal.payload.merge("id" => proposal.id, "status" => proposal.status, "source" => proposal.source,
                           "stale" => proposal.stale?, "created_at" => proposal.created_at, "approved_at" => proposal.approved_at)
  end
end
