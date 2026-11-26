# G1 (goals), plan §2.2 with the step-1 decisions (PO, 2026-11-26): one table
# for the three goal types, type-specific columns checked per type. The saved
# amount and the debt balance are computed from goal_contributions, not
# stored (no current_balance column), so undo-by-delete can't drift.
# Linking a contribution to a transfer (kind linked_transfer, transaction_id)
# is on the cut list and not built. plan_proposal_id arrives with PL1.
# Additive and reversible; foreign keys don't cascade.
class CreateGoals < ActiveRecord::Migration[7.1]
  def change
    create_table :goals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :goal_type, null: false
      t.string :name, null: false
      t.decimal :target_amount, precision: 12, scale: 2
      t.date :target_date
      t.decimal :starting_balance, precision: 12, scale: 2, null: false, default: 0
      t.decimal :apr, precision: 5, scale: 2
      t.decimal :monthly_payment, precision: 12, scale: 2
      t.string :status, null: false, default: "active"
      t.string :source, null: false, default: "user"

      t.timestamps
    end

    add_check_constraint :goals, "goal_type IN ('upcoming_payment','purchase','debt_payoff')", name: "goals_type_check"
    add_check_constraint :goals, "status IN ('active','completed','archived')", name: "goals_status_check"
    add_check_constraint :goals, "source IN ('interview','user','coach')", name: "goals_source_check"
    add_check_constraint :goals, "starting_balance >= 0", name: "goals_starting_balance_check"
    # Saving goals: a target > 0 (and a date for upcoming payments); no debt fields.
    # Debt payoff: a balance > 0, an APR 0-100 and a monthly payment > 0; no target.
    add_check_constraint :goals,
                         "(goal_type IN ('upcoming_payment','purchase') AND target_amount IS NOT NULL AND target_amount > 0 " \
                         "AND apr IS NULL AND monthly_payment IS NULL AND (goal_type = 'purchase' OR target_date IS NOT NULL)) OR " \
                         "(goal_type = 'debt_payoff' AND target_amount IS NULL AND target_date IS NULL AND starting_balance > 0 " \
                         "AND apr IS NOT NULL AND apr >= 0 AND apr <= 100 AND monthly_payment IS NOT NULL AND monthly_payment > 0)",
                         name: "goals_type_fields_check"

    create_table :goal_contributions do |t|
      t.references :goal, null: false, foreign_key: { on_delete: :restrict }
      t.string :kind, null: false
      t.decimal :amount, precision: 12, scale: 2
      t.decimal :balance_after, precision: 12, scale: 2
      t.date :contributed_on, null: false
      t.string :note

      t.timestamps
    end

    add_check_constraint :goal_contributions,
                         "(kind = 'set_aside' AND amount IS NOT NULL AND amount > 0 AND balance_after IS NULL) OR " \
                         "(kind = 'balance_update' AND balance_after IS NOT NULL AND balance_after >= 0 AND amount IS NULL)",
                         name: "goal_contributions_kind_check"
    add_check_constraint :goal_contributions, "note IS NULL OR char_length(note) <= 200", name: "goal_contributions_note_check"
  end
end
