# OB1 (bills): the caller's bills and their paid occurrences. Every lookup
# goes through current_user.obligations (another user's bill → 404); the
# category is a slug from the shared list (unknown → 422; flexible → 422);
# account_id goes through current_user.accounts (another user's → 404).
# "Today" and the 7-day window come from UserClock.
#
#   GET    /obligations                         active bills, each with its current
#                                               occurrence, plus the summary
#   GET    /obligations/due?from=&to=           every due date in the range (≤ 366 days)
#   GET    /obligations/:id
#   POST   /obligations                         { name, amount, category, first_due_on,
#                                                 recurrence, interval, day_of_month,
#                                                 ends_on, account_id }
#   PATCH  /obligations/:id                     same fields
#   POST   /obligations/:id/archive             hides it; history kept (idempotent)
#   POST   /obligations/:id/payments            { due_on, paid_on? } mark paid (idempotent)
#   DELETE /obligations/:id/payments/:due_on    mark unpaid (idempotent)
class Api::V1::ObligationsController < ApplicationController
  include MoneyJson

  MAX_RANGE_DAYS = 366
  FIELDS = %i[name amount first_due_on recurrence interval day_of_month ends_on].freeze

  before_action :require_current_user!
  before_action :set_obligation, only: %i[show update archive pay unpay]

  def index
    obligations = current_user.obligations.active.includes(:category, :payments).order(:name, :id).to_a
    today = UserClock.today(current_user)
    window_end = today + (Bills::WINDOW_DAYS - 1)
    due_soon = Bills.occurrences(obligations, from: today, to: window_end).count { |o| !o.paid? }
    render json: {
      today:,
      window: { start: today, end: window_end },
      summary: { monthly_total: money(Bills.monthly_total(obligations, today:)), due_in_next_7_days: due_soon },
      obligations: obligations.map { |ob| obligation_json(ob, today) },
      assumptions: [Bills::MONTHLY_TOTAL_ASSUMPTION]
    }
  end

  def due
    from = parse_date(params[:from], "from") or return
    to = parse_date(params[:to], "to") or return
    if to < from || (to - from).to_i >= MAX_RANGE_DAYS
      return render json: { error: "invalid_parameter", field: "to" }, status: :unprocessable_entity
    end

    obligations = current_user.obligations.active.includes(:category)
    items = Bills.occurrences(obligations, from:, to:).map do |o|
      { obligation_id: o.obligation.id, name: o.obligation.name, amount: money(o.obligation.amount),
        category: o.obligation.category.slug, due_on: o.due_on, paid: o.paid?, paid_on: o.paid_on }
    end
    render json: { from:, to:, items: }
  end

  def show
    render json: obligation_json(@obligation, UserClock.today(current_user))
  end

  def create
    obligation = current_user.obligations.new(source: "user")
    save(obligation, :created)
  end

  def update
    return render_archived if @obligation.archived?

    save(@obligation, :ok)
  end

  def archive
    @obligation.archive!
    render json: obligation_json(@obligation, UserClock.today(current_user))
  end

  def pay
    return render_archived if @obligation.archived?

    due_on = parse_date(params[:due_on], "due_on") or return
    payment = @obligation.payments.find_by(due_on:)
    status = :ok
    if payment.nil?
      paid_on = params[:paid_on].present? ? parse_date(params[:paid_on], "paid_on") : UserClock.today(current_user)
      return if paid_on.nil?

      payment = @obligation.payments.create!(due_on:, paid_on:)
      status = :created
    end
    render json: payment_json(payment), status:
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid", errors: e.record.errors }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: payment_json(@obligation.payments.find_by!(due_on:)), status: :ok
  end

  def unpay
    due_on = parse_date(params[:due_on], "due_on") or return
    @obligation.payments.where(due_on:).delete_all
    head :no_content
  end

  private

  def set_obligation
    @obligation = current_user.obligations.find(params[:id])
  end

  def save(obligation, status)
    attrs = params.slice(*FIELDS).permit(*FIELDS)
    obligation.assign_attributes(attrs)
    # Owned records first (another user's account → 404), then reference data.
    obligation.account = params[:account_id].present? ? current_user.accounts.find(params[:account_id]) : nil if params.key?(:account_id)
    if params.key?(:category)
      category = Category.active_list.find_by(slug: params[:category].to_s)
      return render_invalid_reference("category") if category.nil?

      obligation.category = category
    end

    if obligation.save
      render json: obligation_json(obligation, UserClock.today(current_user)), status:
    else
      render json: { error: "invalid", errors: obligation.errors }, status: :unprocessable_entity
    end
  end

  def parse_date(value, field)
    Date.iso8601(value.to_s)
  rescue Date::Error
    render json: { error: "invalid_parameter", field: }, status: :unprocessable_entity
    nil
  end

  def render_archived
    render json: { error: "archived" }, status: :unprocessable_entity
  end

  def obligation_json(ob, today)
    current = ob.archived? ? nil : Bills.current(ob, today:)
    { id: ob.id, name: ob.name, amount: money(ob.amount), category: ob.category.slug, category_name: ob.category.name,
      account_id: ob.account_id, first_due_on: ob.first_due_on, recurrence: ob.recurrence, interval: ob.interval,
      day_of_month: ob.day_of_month, ends_on: ob.ends_on, source: ob.source, archived_at: ob.archived_at,
      next_due_on: ob.schedule.next_on_or_after(today), current: }
  end

  def payment_json(payment)
    { obligation_id: payment.obligation_id, due_on: payment.due_on, paid_on: payment.paid_on, paid: true }
  end
end
