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

  # GET /transactions?account_id=&from=&to=&category=&needs_review=&page=&per_page=
  # category: a slug, or "none" for uncategorized rows.
  def index
    scope = current_user.transactions.includes(:category)
    scope = scope.where(account_id: current_user.accounts.find(params[:account_id]).id) if params[:account_id].present?
    scope = scope.where(posted_on: parse_date!(:from)..) if params[:from].present?
    scope = scope.where(posted_on: ..parse_date!(:to)) if params[:to].present?
    scope = filter_by_category(scope) if params[:category].present?
    scope = scope.where(needs_review: ActiveModel::Type::Boolean.new.cast(params[:needs_review])) if params[:needs_review].present?
    return if performed?

    page = [params.fetch(:page, 1).to_i, 1].max
    per_page = params.fetch(:per_page, DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
    rows = scope.order(posted_on: :desc, id: :desc).offset((page - 1) * per_page).limit(per_page)

    render json: { transactions: rows.map { |t| transaction_json(t) }, page:, per_page:, total: scope.count }
  end

  # POST /transactions/categorize - re-run categorization on the caller's
  # rows waiting for review (memory -> rules -> AI). S4-min: at most
  # AiRateLimit::LIMITS[:categorize] per hour per user, and refused before
  # any work once the daily AI cap is reached.
  def categorize
    AiRateLimit.hit!(current_user, :categorize)
    AiBudget.check!(current_user, :categorize)
    summary = Categorization::Pipeline.call(user: current_user, scope: current_user.transactions.where(needs_review: true))
    render json: { categorized: summary.to_h }
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
        @transaction.update!(category: nil, categorization_source: "none", confidence: nil, needs_review: true)
      end
      return render json: transaction_json(@transaction)
    end

    category = Category.active_list.find_by(slug: attrs[:category].to_s)
    return render_invalid_reference("category") if category.nil?
    # Transfers is set only by confirming a transfer pair (TR1).
    return render json: { error: "transfer_category_reserved" }, status: :unprocessable_entity if category.transfer?

    also_updated = ActiveRecord::Base.transaction do
      @transaction.update!(category:, categorization_source: "user", confidence: nil, needs_review: false)
      remember_merchant!(category)
      apply_to_waiting_rows!(category)
    end
    render json: transaction_json(@transaction).merge(also_updated:)
  end

  # DELETE /transactions/1 - removes the row. Importing the same file again
  # would bring it back, since nothing remembers the deletion.
  # Rule for later (PO, 2026-11-24): once TR1 (transfer matching) and G1
  # (goals) exist, a transaction in a transfer link or linked from a goal
  # contribution must return 422 and delete nothing, with tests then.
  def destroy
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

  # AI3: the same user's other rows from this merchant that are still
  # waiting for review get the new category too (source "memory"). Rows the
  # user chose themselves, rows not waiting for review and rows in archived
  # accounts are left alone. Returns how many changed.
  def apply_to_waiting_rows!(category)
    candidates = current_user.transactions.joins(:account).merge(Account.active)
                             .where(needs_review: true).where.not(categorization_source: "user")
                             .where.not(id: @transaction.id)
                             .pluck(:id, :normalized_description)
    ids = candidates.select { |_, normalized| Categorization::MerchantKey.for(normalized) == merchant_key }.map(&:first)
    return 0 if ids.empty?

    Transaction.where(id: ids).update_all(category_id: category.id, categorization_source: "memory", confidence: nil,
                                          needs_review: false, updated_at: Time.current)
  end

  # One atomic INSERT ... ON CONFLICT, so two requests at once can't clash;
  # `hits` restarts when the category changes.
  def remember_merchant!(category)
    now = Time.current
    MerchantRule.upsert(
      { user_id: current_user.id, merchant_key:,
        category_id: category.id, hits: 0, created_at: now, updated_at: now },
      unique_by: %i[user_id merchant_key],
      on_duplicate: Arel.sql(<<~SQL.squish)
        hits = CASE WHEN merchant_rules.category_id = EXCLUDED.category_id THEN merchant_rules.hits ELSE 0 END,
        category_id = EXCLUDED.category_id, updated_at = EXCLUDED.updated_at
      SQL
    )
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

  def transaction_json(t)
    {
      id: t.id, account_id: t.account_id, import_id: t.import_id, posted_on: t.posted_on,
      amount: money(t.amount), description: t.description, external_id: t.external_id,
      category: t.category&.slug, categorization_source: t.categorization_source,
      confidence: t.confidence&.to_s("F"), needs_review: t.needs_review, created_at: t.created_at
    }
  end
end
