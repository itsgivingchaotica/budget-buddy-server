# OB1 (bills), plan §2.2: a recurring bill with a structured schedule, and one
# row per paid occurrence. Additive and reversible; foreign keys don't
# cascade (bills are archived, never deleted). plan_proposal_id arrives with
# PL1.
#
# day_of_month (not in plan §2.2): the day a monthly or yearly bill is due,
# kept separately from first_due_on so "monthly on the 31st" starting in a
# 30-day month still lands on the 31st later (SCREENS_PLAN §4: days 29-31
# fall on the month's last day when it's shorter).
class CreateObligations < ActiveRecord::Migration[7.1]
  def change
    create_table :obligations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.references :category, null: false, foreign_key: true
      t.references :account, foreign_key: true
      t.date :first_due_on, null: false
      t.string :recurrence, null: false, default: "monthly"
      t.integer :interval, null: false, default: 1
      t.integer :day_of_month
      t.date :ends_on
      t.string :source, null: false, default: "user"
      t.datetime :archived_at

      t.timestamps
    end

    add_check_constraint :obligations, "amount > 0", name: "obligations_amount_check"
    add_check_constraint :obligations, "recurrence IN ('none','weekly','biweekly','monthly','yearly')", name: "obligations_recurrence_check"
    add_check_constraint :obligations, '"interval" >= 1', name: "obligations_interval_check"
    add_check_constraint :obligations,
                         "(recurrence IN ('monthly','yearly') AND day_of_month IS NOT NULL AND day_of_month BETWEEN 1 AND 31) OR " \
                         "(recurrence NOT IN ('monthly','yearly') AND day_of_month IS NULL)",
                         name: "obligations_day_of_month_check"
    add_check_constraint :obligations, "ends_on IS NULL OR ends_on >= first_due_on", name: "obligations_ends_on_check"
    add_check_constraint :obligations, "source IN ('interview','user','coach')", name: "obligations_source_check"

    create_table :obligation_payments do |t|
      t.references :obligation, null: false, foreign_key: { on_delete: :restrict }, index: false
      t.date :due_on, null: false
      t.date :paid_on, null: false

      t.timestamps
    end

    add_index :obligation_payments, %i[obligation_id due_on], unique: true
  end
end
