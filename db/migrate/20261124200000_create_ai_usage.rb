# S4-min (rate limit and AI cost cap): per-user, per-day, per-feature Claude
# usage, read by AiBudget before every Claude call (plan §2.2 "AI usage").
# "day" is the UTC date. Additive and reversible.
class CreateAiUsage < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_usage do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.date :day, null: false
      t.string :feature, null: false
      t.integer :requests, null: false, default: 0
      t.bigint :input_tokens, null: false, default: 0
      t.bigint :output_tokens, null: false, default: 0

      t.timestamps
    end

    add_index :ai_usage, %i[user_id day feature], unique: true
    add_check_constraint :ai_usage, "feature IN ('categorize','onboarding','plan','assistant')", name: "ai_usage_feature_check"
    add_check_constraint :ai_usage, "requests >= 0 AND input_tokens >= 0 AND output_tokens >= 0", name: "ai_usage_counts_check"
  end
end
