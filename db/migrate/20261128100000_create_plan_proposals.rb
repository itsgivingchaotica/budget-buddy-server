# PL1 (plan drafting), SPEC_ONBOARDING_PLAN §6.4 and D-032 (plan drafting
# and approval details): the coach's draft plan, stored server-side and never
# as live plan rows until PL2 (plan approval). `payload` holds every Rails
# figure plus the model's text. Statuses draft / approved / superseded; stale
# is worked out on read, not stored. At most one open draft per user.
# Additive and reversible; the foreign key doesn't cascade. The links from
# category_budgets / obligations / goals back to a proposal arrive with PL2.
class CreatePlanProposals < ActiveRecord::Migration[7.1]
  def change
    create_table :plan_proposals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.string :source, null: false
      t.string :model
      t.jsonb :payload, null: false, default: {}
      t.datetime :approved_at

      t.timestamps
    end

    add_check_constraint :plan_proposals, "status IN ('draft','approved','superseded')", name: "plan_proposals_status_check"
    add_check_constraint :plan_proposals, "source IN ('model','fallback')", name: "plan_proposals_source_check"
    add_check_constraint :plan_proposals, "(status = 'approved') = (approved_at IS NOT NULL)", name: "plan_proposals_approved_at_check"
    add_index :plan_proposals, :user_id, unique: true, where: "status = 'draft'", name: "index_plan_proposals_one_draft_per_user"
  end
end
