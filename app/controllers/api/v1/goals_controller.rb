# G1 (goals): the caller's goals and their contributions. Every lookup goes
# through current_user.goals (another user's goal or contribution → 404).
# Saved amounts and debt balances are computed (Goal#saved / #balance); each
# goal also carries `progress` from GoalCalculator (G2: weekly need, on
# track, milestones; debt interest, payoff and a what-if), so the app does
# no maths. `what_if_extra` (default 50) is the debt what-if step.
#
#   GET    /goals?status=active|completed|archived|all   (default active), ordered:
#                                         dated saving goals by date, undated, then debt
#   GET    /goals/:id                     with its contributions, newest first
#   POST   /goals                         { goal_type, name, target_amount, target_date,
#                                           starting_balance, apr, monthly_payment }
#                                         (no "+ Add goal" in the app; for PL2 and demo data)
#   PATCH  /goals/:id                     same fields except goal_type, plus status
#   POST   /goals/:id/contributions       { kind?, amount | balance_after, contributed_on?, note? }
#                                         kind defaults to set_aside (saving) / balance_update (debt)
#   DELETE /goals/:id/contributions/:cid  undo
class Api::V1::GoalsController < ApplicationController
  include MoneyJson
  include AnalyticsJson

  FIELDS = %i[name target_amount target_date starting_balance apr monthly_payment].freeze

  MAX_WHAT_IF = BigDecimal("1000000")

  before_action :require_current_user!
  before_action :set_what_if
  before_action :set_goal, only: %i[show update contribute uncontribute]

  def index
    status = params[:status].presence || "active"
    unless status == "all" || Goal::STATUSES.include?(status)
      return render json: { error: "invalid_parameter", field: "status" }, status: :unprocessable_entity
    end

    goals = current_user.goals.includes(:contributions)
    goals = goals.where(status:) unless status == "all"
    render json: { goals: sort(goals.to_a).map { |g| goal_json(g) } }
  end

  def show
    render json: goal_json(@goal).merge(contributions: @goal.contributions.sort_by { |c| [c.contributed_on, c.id] }.reverse.map { |c| contribution_json(c) })
  end

  def create
    goal = current_user.goals.new(params.slice(*FIELDS, :goal_type).permit(*FIELDS, :goal_type).merge(source: "user"))
    goal.starting_balance ||= 0
    save(goal, :created)
  end

  def update
    @goal.assign_attributes(params.slice(*FIELDS, :status).permit(*FIELDS, :status))
    @goal.starting_balance ||= 0
    save(@goal, :ok)
  end

  def contribute
    return render json: { error: "archived" }, status: :unprocessable_entity if @goal.status == "archived"

    kind = params[:kind].presence || (@goal.debt? ? "balance_update" : "set_aside")
    on = params[:contributed_on].present? ? parse_date(params[:contributed_on]) : UserClock.today(current_user)
    return if on.nil?

    contribution = @goal.contributions.new(kind:, amount: params[:amount], balance_after: params[:balance_after],
                                           contributed_on: on, note: params[:note])
    if contribution.save
      render json: { contribution: contribution_json(contribution), goal: goal_json(@goal.reload) }, status: :created
    else
      render json: { error: "invalid", errors: contribution.errors }, status: :unprocessable_entity
    end
  end

  def uncontribute
    @goal.contributions.find(params[:contribution_id]).destroy!
    render json: { goal: goal_json(@goal.reload) }
  end

  private

  def set_what_if
    @what_if = params[:what_if_extra].present? ? BigDecimal(params[:what_if_extra].to_s) : GoalCalculator::DEFAULT_WHAT_IF
    raise ArgumentError unless @what_if.positive? && @what_if <= MAX_WHAT_IF
  rescue ArgumentError, TypeError
    render json: { error: "invalid_parameter", field: "what_if_extra" }, status: :unprocessable_entity
  end

  def set_goal
    @goal = current_user.goals.find(params[:id])
  end

  def save(goal, status)
    if goal.save
      render json: goal_json(goal), status:
    else
      render json: { error: "invalid", errors: goal.errors }, status: :unprocessable_entity
    end
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    render json: { error: "invalid_parameter", field: "contributed_on" }, status: :unprocessable_entity
    nil
  end

  # Dated saving goals by date, then undated saving goals, then debts.
  def sort(goals)
    goals.sort_by do |g|
      group = if g.debt? then 2 elsif g.target_date then 0 else 1 end
      [group, g.target_date || Date.new(9999), g.name.downcase, g.id]
    end
  end

  def goal_json(g)
    { id: g.id, goal_type: g.goal_type, name: g.name, status: g.status, source: g.source,
      target_amount: money(g.target_amount), target_date: g.target_date, starting_balance: money(g.starting_balance),
      apr: money(g.apr), monthly_payment: money(g.monthly_payment),
      saved: money(g.saved), balance: money(g.balance), remaining: money(g.remaining),
      progress: analytics_json(GoalCalculator.for(g, what_if_extra: @what_if).call) }
  end

  def contribution_json(c)
    { id: c.id, goal_id: c.goal_id, kind: c.kind, amount: money(c.amount), balance_after: money(c.balance_after),
      contributed_on: c.contributed_on, note: c.note }
  end
end
