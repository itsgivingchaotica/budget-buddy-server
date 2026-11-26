# I2 (import endpoint): the caller's transactions. Every lookup goes through
# current_user.transactions (owned through accounts, AD2), so another user's
# transaction is a 404. Categories are referenced by slug from the shared
# list; an unknown one is a 422. Transactions in archived accounts are
# read-only, like the account itself (DM-2).
class Api::V1::TransactionsController < ApplicationController
  include MoneyJson

  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 200

  before_action :require_current_user!
  before_action :set_transaction, only: %i[update destroy]
  before_action :refuse_if_archived, only: %i[update destroy]

  # GET /transactions?account_id=&import_id=&from=&to=&category=&needs_review=&page=&per_page=
  # category: a slug, or "none" for uncategorized rows.
  def index
    scope = current_user.transactions.includes(:category, :suggested_category)
    scope = scope.where(account_id: current_user.accounts.find(params[:account_id]).id) if params[:account_id].present?
    # C2: the import result screen counts one import's rows. Another user's import -> 404.
    scope = scope.where(import_id: current_user.imports.find(params[:import_id]).id) if params[:import_id].present?
    scope = scope.where(posted_on: parse_date!(:from)..) if params[:from].present?
    scope = scope.where(posted_on: ..parse_date!(:to)) if params[:to].present?
    scope = filter_by_category(scope) if params[:category].present?
    scope = scope.where(needs_review: ActiveModel::Type::Boolean.new.cast(params[:needs_review])) if params[:needs_review].present?
    return if performed?

    page = [params.fetch(:page, 1).to_i, 1].max
    per_page = params.fetch(:per_page, DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
    rows = scope.order(posted_on: :desc, id: :desc).offset((page - 1) * per_page).limit(per_page)

    in_suggested_pairs = TransferLink.where(user: current_user, status: "suggested")
                                     .pluck(:outflow_transaction_id, :inflow_transaction_id).flatten.to_set
    render json: { transactions: rows.map { |t| transaction_json(t, in_suggested_pairs) }, page:, per_page:, total: scope.count }
  end

  # POST /transactions/categorize - categorize the caller's uncategorized
  # rows (memory -> rules -> Claude). AI2: Claude sees at most
  # Pipeline::AI_ROWS_PER_RUN rows per call, each row once; the client calls
  # again while `remaining` > 0. S4-min: at most AiRateLimit::LIMITS[:categorize]
  # per hour per user, and refused before any work once the daily AI cap is
  # reached.
  def categorize
    AiRateLimit.hit!(current_user, :categorize)
    AiBudget.check!(current_user, :categorize)
    summary = Categorization::Pipeline.call(user: current_user, scope: current_user.transactions)
    render json: { processed: summary.processed, remaining: summary.remaining, categorized: summary.to_h }
  rescue AiRateLimit::Limited => e
    response.set_header("Retry-After", e.retry_after.to_s)
    render json: { error: "rate_limited", retry_after: e.retry_after }, status: :too_many_requests
  rescue AiBudget::Exceeded
    render json: { error: "ai_daily_cap_reached" }, status: :too_many_requests
  end

  # PATCH /transactions/1  { transaction: { category: "groceries" } }  (or null to clear)
  # Only the category can change; it becomes the user's choice.
  def update
    attrs = params.fetch(:transaction, {})
    return render json: { error: "category_required" }, status: :unprocessable_entity unless attrs.key?(:category)

    if attrs[:category].blank?
      # Cleared rows go back to review; categorization isn't re-run. If the
      # category came from merchant memory, that memory was wrong, so it's
      # forgotten (PO, 2026-11-24). Other sources leave memory alone.
      ActiveRecord::Base.transaction do
        forget_merchant! if @transaction.categorization_source == "memory"
        # ai_attempted_at: the AI must not re-categorize a row the user cleared (AI2).
        @transaction.update!(category: nil, categorization_source: "none", confidence: nil, needs_review: true,
                             ai_attempted_at: Time.current)
      end
      return render json: transaction_json(@transaction)
    end

    category = Category.active_list.find_by(slug: attrs[:category].to_s)
    return render_invalid_reference("category") if category.nil?
    # Transfers is set only by confirming a transfer pair (TR1).
    return render json: { error: "transfer_category_reserved" }, status: :unprocessable_entity if category.transfer?

    # AI3 + C2b: set the category, teach merchant memory, update the
    # merchant's other waiting rows, and record the correction for Undo.
    correction, also_updated = Categorization::Correction.apply(user: current_user, transaction: @transaction, category:)
    render json: transaction_json(@transaction.reload).merge(also_updated:, correction_id: correction.id)
  end

  # GET /transactions/review_groups - the Review screen (handoff #05 §B.3):
  # rows waiting for review, not in a suggested transfer pair, grouped by
  # merchant, with a suggestion and alternatives per group.
  def review_groups
    render json: { remaining: Categorization::Review.remaining(current_user), groups: Categorization::Review.groups(current_user) }
  end

  # DELETE /transactions/1 - removes the row. Importing the same file again
  # would bring it back, since nothing remembers the deletion.
  # PO rule (2026-11-24): a transaction in any transfer link (TR1) can't be
  # deleted: 422, nothing deleted. (Goal contributions get the same rule
  # with G1.)
  def destroy
    if TransferLink.involving(@transaction.id).exists?
      return render json: { error: "in_transfer_link" }, status: :unprocessable_entity
    end

    @transaction.destroy!
    head :no_content
  end

  private

  def set_transaction
    @transaction = current_user.transactions.find(params[:id])
  end

  # AI3 (learning from corrections): the user's choice becomes merchant
  # memory, so the next import of this merchant uses it (source "memory")
  # before rules or AI. One rule per user and merchant; a new choice replaces
  # the old one. Clearing a category doesn't change memory.
  def merchant_key
    @merchant_key ||= Categorization::MerchantKey.for(@transaction.normalized_description)
  end

  def forget_merchant!
    current_user.merchant_rules.where(merchant_key:).delete_all
  end



  def refuse_if_archived
    render json: { error: "archived" }, status: :unprocessable_entity if @transaction.account.archived?
  end

  def parse_date!(name)
    Date.iso8601(params[name].to_s)
  rescue Date::Error
    render json: { error: "invalid_parameter", field: name.to_s }, status: :unprocessable_entity unless performed?
    nil
  end

  def filter_by_category(scope)
    return scope.uncategorized if params[:category] == "none"

    category = Category.active_list.find_by(slug: params[:category].to_s)
    return scope.where(category_id: category.id) if category

    render_invalid_reference("category") unless performed?
    scope
  end

  # C2b: `suggested_category` (slug) is Claude's unsure pick, shown as
  # "<Category>?"; `transfer_suggested` marks rows in a suggested transfer
  # pair ("Transfer?").
  def transaction_json(t, in_suggested_pairs = nil)
    in_suggested_pairs ||= TransferLink.where(user: current_user, status: "suggested").involving(t.id)
                                       .pluck(:outflow_transaction_id, :inflow_transaction_id).flatten.to_set
    {
      id: t.id, account_id: t.account_id, import_id: t.import_id, posted_on: t.posted_on,
      amount: money(t.amount), description: t.description, external_id: t.external_id,
      category: t.category&.slug, suggested_category: t.suggested_category&.slug,
      categorization_source: t.categorization_source, confidence: t.confidence&.to_s("F"),
      needs_review: t.needs_review, transfer_suggested: in_suggested_pairs.include?(t.id), created_at: t.created_at
    }
  end
end
