# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_11_26_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "purpose", null: false
    t.string "purpose_note"
    t.decimal "opening_balance", precision: 12, scale: 2
    t.date "opening_balance_on"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "user_id, lower((name)::text)", name: "index_accounts_on_user_id_and_lower_name", unique: true
    t.index ["user_id"], name: "index_accounts_on_user_id"
    t.check_constraint "(opening_balance IS NULL) = (opening_balance_on IS NULL)", name: "accounts_opening_balance_pair_check"
    t.check_constraint "kind::text = ANY (ARRAY['checking'::character varying, 'savings'::character varying, 'credit_card'::character varying, 'p2p'::character varying, 'cash'::character varying, 'other'::character varying]::text[])", name: "accounts_kind_check"
    t.check_constraint "length(btrim(name::text)) >= 1 AND length(btrim(name::text)) <= 60", name: "accounts_name_length_check"
    t.check_constraint "purpose::text = ANY (ARRAY['spending'::character varying, 'bills'::character varying, 'savings'::character varying, 'side_income'::character varying, 'other'::character varying]::text[])", name: "accounts_purpose_check"
  end

  create_table "ai_usage", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "day", null: false
    t.string "feature", null: false
    t.integer "requests", default: 0, null: false
    t.bigint "input_tokens", default: 0, null: false
    t.bigint "output_tokens", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "day", "feature"], name: "index_ai_usage_on_user_id_and_day_and_feature", unique: true
    t.check_constraint "feature::text = ANY (ARRAY['categorize'::character varying, 'onboarding'::character varying, 'plan'::character varying, 'assistant'::character varying]::text[])", name: "ai_usage_feature_check"
    t.check_constraint "requests >= 0 AND input_tokens >= 0 AND output_tokens >= 0", name: "ai_usage_counts_check"
  end

  create_table "budgets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_budgets_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category_type"
    t.string "slug"
    t.string "kind", null: false
    t.boolean "active", default: false, null: false
    t.integer "position"
    t.string "need_want"
    t.string "fixed_variable"
    t.string "recurrence_label"
    t.index ["slug"], name: "index_categories_on_slug", unique: true
    t.check_constraint "fixed_variable IS NULL OR (fixed_variable::text = ANY (ARRAY['fixed'::character varying, 'variable'::character varying]::text[]))", name: "categories_fixed_variable_check"
    t.check_constraint "kind::text <> 'spending'::text OR fixed_variable IS NOT NULL", name: "categories_spending_needs_fixed_variable"
    t.check_constraint "kind::text = 'legacy'::text OR slug IS NOT NULL", name: "categories_slug_required"
    t.check_constraint "kind::text = ANY (ARRAY['spending'::character varying, 'income'::character varying, 'transfer'::character varying, 'legacy'::character varying]::text[])", name: "categories_kind_check"
    t.check_constraint "need_want IS NULL OR (need_want::text = ANY (ARRAY['need'::character varying, 'want'::character varying]::text[]))", name: "categories_need_want_check"
    t.check_constraint "recurrence_label IS NULL OR (recurrence_label::text = ANY (ARRAY['one_time'::character varying, 'recurring'::character varying]::text[]))", name: "categories_recurrence_label_check"
  end

  create_table "category_budgets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "category_id", null: false
    t.string "period", default: "month", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.date "effective_from", null: false
    t.string "source", default: "user", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_category_budgets_on_category_id"
    t.index ["user_id", "category_id", "effective_from"], name: "index_category_budgets_on_user_category_month", unique: true
    t.check_constraint "EXTRACT(day FROM effective_from) = 1::numeric", name: "category_budgets_first_of_month_check"
    t.check_constraint "amount >= 0::numeric", name: "category_budgets_amount_check"
    t.check_constraint "period::text = 'month'::text", name: "category_budgets_period_check"
    t.check_constraint "source::text = ANY (ARRAY['user'::character varying, 'coach'::character varying]::text[])", name: "category_budgets_source_check"
  end

  create_table "category_corrections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "transaction_id", null: false
    t.bigint "new_category_id", null: false
    t.string "merchant_key", null: false
    t.jsonb "previous", default: [], null: false
    t.jsonb "merchant_rule_before"
    t.datetime "undone_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["new_category_id"], name: "index_category_corrections_on_new_category_id"
    t.index ["transaction_id"], name: "index_category_corrections_on_transaction_id"
    t.index ["user_id"], name: "index_category_corrections_on_user_id"
    t.check_constraint "jsonb_typeof(previous) = 'array'::text", name: "category_corrections_previous_array_check"
  end

  create_table "entries", force: :cascade do |t|
    t.bigint "budget_id", null: false
    t.date "start_date"
    t.decimal "amount"
    t.text "description"
    t.string "frequency"
    t.text "custom_frequency_days"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "category_id"
    t.integer "frequency_number"
    t.date "end_date"
    t.index ["budget_id"], name: "index_entries_on_budget_id"
    t.index ["category_id"], name: "index_entries_on_category_id"
  end

  create_table "entries_tags", id: false, force: :cascade do |t|
    t.bigint "entry_id", null: false
    t.bigint "tag_id", null: false
    t.bigint "user_id"
    t.bigint "budget_id"
    t.index ["budget_id"], name: "index_entries_tags_on_budget_id"
    t.index ["entry_id"], name: "index_entries_tags_on_entry_id"
    t.index ["tag_id"], name: "index_entries_tags_on_tag_id"
    t.index ["user_id"], name: "index_entries_tags_on_user_id"
  end

  create_table "financial_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.jsonb "answers", default: {}, null: false
    t.integer "answers_version"
    t.string "pay_frequency"
    t.date "next_pay_on"
    t.decimal "typical_pay_amount", precision: 12, scale: 2
    t.string "change_appetite"
    t.integer "week_starts_on", default: 1, null: false
    t.string "time_zone"
    t.datetime "onboarding_completed_at"
    t.jsonb "coach_notes", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_financial_profiles_on_user_id", unique: true
  end

  create_table "goal_contributions", force: :cascade do |t|
    t.bigint "goal_id", null: false
    t.string "kind", null: false
    t.decimal "amount", precision: 12, scale: 2
    t.decimal "balance_after", precision: 12, scale: 2
    t.date "contributed_on", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["goal_id"], name: "index_goal_contributions_on_goal_id"
    t.check_constraint "kind::text = 'set_aside'::text AND amount IS NOT NULL AND amount > 0::numeric AND balance_after IS NULL OR kind::text = 'balance_update'::text AND balance_after IS NOT NULL AND balance_after >= 0::numeric AND amount IS NULL", name: "goal_contributions_kind_check"
    t.check_constraint "note IS NULL OR char_length(note::text) <= 200", name: "goal_contributions_note_check"
  end

  create_table "goals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "goal_type", null: false
    t.string "name", null: false
    t.decimal "target_amount", precision: 12, scale: 2
    t.date "target_date"
    t.decimal "starting_balance", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "apr", precision: 5, scale: 2
    t.decimal "monthly_payment", precision: 12, scale: 2
    t.string "status", default: "active", null: false
    t.string "source", default: "user", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_goals_on_user_id"
    t.check_constraint "(goal_type::text = ANY (ARRAY['upcoming_payment'::character varying, 'purchase'::character varying]::text[])) AND target_amount IS NOT NULL AND target_amount > 0::numeric AND apr IS NULL AND monthly_payment IS NULL AND (goal_type::text = 'purchase'::text OR target_date IS NOT NULL) OR goal_type::text = 'debt_payoff'::text AND target_amount IS NULL AND target_date IS NULL AND starting_balance > 0::numeric AND apr IS NOT NULL AND apr >= 0::numeric AND apr <= 100::numeric AND monthly_payment IS NOT NULL AND monthly_payment > 0::numeric", name: "goals_type_fields_check"
    t.check_constraint "goal_type::text = ANY (ARRAY['upcoming_payment'::character varying, 'purchase'::character varying, 'debt_payoff'::character varying]::text[])", name: "goals_type_check"
    t.check_constraint "source::text = ANY (ARRAY['interview'::character varying, 'user'::character varying, 'coach'::character varying]::text[])", name: "goals_source_check"
    t.check_constraint "starting_balance >= 0::numeric", name: "goals_starting_balance_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'completed'::character varying, 'archived'::character varying]::text[])", name: "goals_status_check"
  end

  create_table "imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "filename", null: false
    t.string "status", default: "processing", null: false
    t.integer "row_count", default: 0, null: false
    t.integer "inserted_count", default: 0, null: false
    t.integer "duplicate_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.jsonb "row_errors", default: [], null: false
    t.date "data_from"
    t.date "data_through"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_imports_on_account_id"
    t.index ["id", "account_id"], name: "index_imports_on_id_and_account_id", unique: true
    t.check_constraint "data_from IS NULL OR data_through IS NULL OR data_from <= data_through", name: "imports_data_range_check"
    t.check_constraint "jsonb_typeof(row_errors) = 'array'::text", name: "imports_row_errors_array_check"
    t.check_constraint "length(btrim(filename::text)) >= 1 AND length(btrim(filename::text)) <= 255", name: "imports_filename_length_check"
    t.check_constraint "row_count >= 0 AND inserted_count >= 0 AND duplicate_count >= 0 AND error_count >= 0", name: "imports_counts_check"
    t.check_constraint "status::text = ANY (ARRAY['processing'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "imports_status_check"
  end

  create_table "merchant_rules", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "merchant_key", null: false
    t.bigint "category_id", null: false
    t.integer "hits", default: 0, null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_merchant_rules_on_category_id"
    t.index ["user_id", "merchant_key"], name: "index_merchant_rules_on_user_id_and_merchant_key", unique: true
    t.check_constraint "hits >= 0", name: "merchant_rules_hits_check"
    t.check_constraint "length(merchant_key::text) >= 1 AND length(merchant_key::text) <= 255", name: "merchant_rules_key_length_check"
  end

  create_table "obligation_payments", force: :cascade do |t|
    t.bigint "obligation_id", null: false
    t.date "due_on", null: false
    t.date "paid_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["obligation_id", "due_on"], name: "index_obligation_payments_on_obligation_id_and_due_on", unique: true
  end

  create_table "obligations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.bigint "category_id", null: false
    t.bigint "account_id"
    t.date "first_due_on", null: false
    t.string "recurrence", default: "monthly", null: false
    t.integer "interval", default: 1, null: false
    t.integer "day_of_month"
    t.date "ends_on"
    t.string "source", default: "user", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_obligations_on_account_id"
    t.index ["category_id"], name: "index_obligations_on_category_id"
    t.index ["user_id"], name: "index_obligations_on_user_id"
    t.check_constraint "(recurrence::text = ANY (ARRAY['monthly'::character varying, 'yearly'::character varying]::text[])) AND day_of_month IS NOT NULL AND day_of_month >= 1 AND day_of_month <= 31 OR (recurrence::text <> ALL (ARRAY['monthly'::character varying, 'yearly'::character varying]::text[])) AND day_of_month IS NULL", name: "obligations_day_of_month_check"
    t.check_constraint "\"interval\" >= 1", name: "obligations_interval_check"
    t.check_constraint "amount > 0::numeric", name: "obligations_amount_check"
    t.check_constraint "ends_on IS NULL OR ends_on >= first_due_on", name: "obligations_ends_on_check"
    t.check_constraint "recurrence::text = ANY (ARRAY['none'::character varying, 'weekly'::character varying, 'biweekly'::character varying, 'monthly'::character varying, 'yearly'::character varying]::text[])", name: "obligations_recurrence_check"
    t.check_constraint "source::text = ANY (ARRAY['interview'::character varying, 'user'::character varying, 'coach'::character varying]::text[])", name: "obligations_source_check"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.boolean "default_tag", default: false
    t.bigint "category_id"
    t.index ["category_id"], name: "index_tags_on_category_id"
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "import_id"
    t.date "posted_on", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "description", null: false
    t.string "normalized_description", null: false
    t.string "external_id"
    t.string "base_key", null: false
    t.integer "occurrence", default: 1, null: false
    t.bigint "category_id"
    t.string "categorization_source", default: "none", null: false
    t.decimal "confidence", precision: 4, scale: 3
    t.boolean "needs_review", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "ai_attempted_at"
    t.bigint "suggested_category_id"
    t.index ["account_id", "base_key", "occurrence"], name: "index_transactions_on_account_base_key_occurrence", unique: true
    t.index ["account_id", "external_id"], name: "index_transactions_on_account_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["account_id", "posted_on"], name: "index_transactions_on_account_id_and_posted_on"
    t.index ["account_id"], name: "index_transactions_awaiting_ai", where: "(((categorization_source)::text = 'none'::text) AND (ai_attempted_at IS NULL))"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["import_id"], name: "index_transactions_on_import_id"
    t.index ["suggested_category_id"], name: "index_transactions_on_suggested_category_id"
    t.check_constraint "(categorization_source::text = 'none'::text) = (category_id IS NULL)", name: "transactions_source_matches_category_check"
    t.check_constraint "amount <> 0::numeric", name: "transactions_amount_nonzero_check"
    t.check_constraint "base_key::text ~ '^[0-9a-f]{64}$'::text", name: "transactions_base_key_format_check"
    t.check_constraint "categorization_source::text = ANY (ARRAY['user'::character varying, 'memory'::character varying, 'rule'::character varying, 'ai'::character varying, 'transfer'::character varying, 'none'::character varying]::text[])", name: "transactions_categorization_source_check"
    t.check_constraint "confidence IS NULL OR confidence >= 0::numeric AND confidence <= 1::numeric", name: "transactions_confidence_range_check"
    t.check_constraint "external_id IS NULL OR length(btrim(external_id::text)) >= 1 AND length(btrim(external_id::text)) <= 255", name: "transactions_external_id_length_check"
    t.check_constraint "length(btrim(description::text)) >= 1 AND length(btrim(description::text)) <= 255", name: "transactions_description_length_check"
    t.check_constraint "length(normalized_description::text) >= 1 AND length(normalized_description::text) <= 255", name: "transactions_normalized_description_length_check"
    t.check_constraint "occurrence >= 1", name: "transactions_occurrence_check"
    t.check_constraint "suggested_category_id IS NULL OR category_id IS NULL", name: "transactions_suggestion_only_when_uncategorized_check"
  end

  create_table "transfer_links", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "outflow_transaction_id", null: false
    t.bigint "inflow_transaction_id", null: false
    t.string "status", default: "suggested", null: false
    t.integer "days_apart", null: false
    t.jsonb "previous_state"
    t.datetime "confirmed_at"
    t.datetime "rejected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inflow_transaction_id"], name: "index_transfer_links_active_inflow", unique: true, where: "((status)::text = ANY ((ARRAY['suggested'::character varying, 'confirmed'::character varying])::text[]))"
    t.index ["inflow_transaction_id"], name: "index_transfer_links_on_inflow"
    t.index ["outflow_transaction_id", "inflow_transaction_id"], name: "index_transfer_links_on_pair", unique: true
    t.index ["outflow_transaction_id"], name: "index_transfer_links_active_outflow", unique: true, where: "((status)::text = ANY ((ARRAY['suggested'::character varying, 'confirmed'::character varying])::text[]))"
    t.index ["user_id"], name: "index_transfer_links_on_user_id"
    t.check_constraint "days_apart >= 0 AND days_apart <= 3", name: "transfer_links_days_apart_check"
    t.check_constraint "outflow_transaction_id <> inflow_transaction_id", name: "transfer_links_distinct_rows_check"
    t.check_constraint "status::text = ANY (ARRAY['suggested'::character varying, 'confirmed'::character varying, 'rejected'::character varying]::text[])", name: "transfer_links_status_check"
  end

  create_table "users", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "picture"
    t.string "kinde_id"
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["kinde_id"], name: "index_users_on_kinde_id", unique: true
  end

  add_foreign_key "accounts", "users"
  add_foreign_key "ai_usage", "users"
  add_foreign_key "budgets", "users"
  add_foreign_key "category_budgets", "categories"
  add_foreign_key "category_budgets", "users"
  add_foreign_key "category_corrections", "categories", column: "new_category_id"
  add_foreign_key "category_corrections", "transactions"
  add_foreign_key "category_corrections", "users"
  add_foreign_key "entries", "budgets"
  add_foreign_key "entries", "categories"
  add_foreign_key "entries_tags", "budgets"
  add_foreign_key "entries_tags", "users"
  add_foreign_key "financial_profiles", "users"
  add_foreign_key "goal_contributions", "goals", on_delete: :restrict
  add_foreign_key "goals", "users"
  add_foreign_key "imports", "accounts"
  add_foreign_key "merchant_rules", "categories"
  add_foreign_key "merchant_rules", "users"
  add_foreign_key "obligation_payments", "obligations", on_delete: :restrict
  add_foreign_key "obligations", "accounts"
  add_foreign_key "obligations", "categories"
  add_foreign_key "obligations", "users"
  add_foreign_key "tags", "categories"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "categories", column: "suggested_category_id"
  add_foreign_key "transactions", "imports", column: ["import_id", "account_id"], primary_key: ["id", "account_id"], name: "fk_transactions_import_same_account"
  add_foreign_key "transfer_links", "transactions", column: "inflow_transaction_id"
  add_foreign_key "transfer_links", "transactions", column: "outflow_transaction_id"
  add_foreign_key "transfer_links", "users"
end
