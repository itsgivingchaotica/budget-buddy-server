# S2 / plan §2.2: one financial profile per user. Answers live in jsonb; every
# value a calculation reads is a typed column. Additive and reversible.
class CreateFinancialProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :answers, null: false, default: {}
      t.integer :answers_version
      t.string :pay_frequency
      t.date :next_pay_on
      t.decimal :typical_pay_amount, precision: 12, scale: 2
      t.string :change_appetite
      t.integer :week_starts_on, null: false, default: 1 # Ruby wday; 1 = Monday (PO-12)
      t.string :time_zone # IANA name; null until the client sends one (PO-12)
      t.datetime :onboarding_completed_at
      t.jsonb :coach_notes, null: false, default: {}

      t.timestamps
    end
  end
end
