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

ActiveRecord::Schema[7.1].define(version: 2026_11_25_100000) do
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
    t.index ["account_id", "base_key", "occurrence"], name: "index_transactions_on_account_base_key_occurrence", unique: true
    t.index ["account_id", "external_id"], name: "index_transactions_on_account_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["account_id", "posted_on"], name: "index_transactions_on_account_id_and_posted_on"
    t.index ["account_id"], name: "index_transactions_awaiting_ai", where: "(((categorization_source)::text = 'none'::text) AND (ai_attempted_at IS NULL))"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["import_id"], name: "index_transactions_on_import_id"
    t.check_constraint "(categorization_source::text = 'none'::text) = (category_id IS NULL)", name: "transactions_source_matches_category_check"
    t.check_constraint "amount <> 0::numeric", name: "transactions_amount_nonzero_check"
    t.check_constraint "base_key::text ~ '^[0-9a-f]{64}$'::text", name: "transactions_base_key_format_check"
    t.check_constraint "categorization_source::text = ANY (ARRAY['user'::character varying, 'memory'::character varying, 'rule'::character varying, 'ai'::character varying, 'transfer'::character varying, 'none'::character varying]::text[])", name: "transactions_categorization_source_check"
    t.check_constraint "confidence IS NULL OR confidence >= 0::numeric AND confidence <= 1::numeric", name: "transactions_confidence_range_check"
    t.check_constraint "external_id IS NULL OR length(btrim(external_id::text)) >= 1 AND length(btrim(external_id::text)) <= 255", name: "transactions_external_id_length_check"
    t.check_constraint "length(btrim(description::text)) >= 1 AND length(btrim(description::text)) <= 255", name: "transactions_description_length_check"
    t.check_constraint "length(normalized_description::text) >= 1 AND length(normalized_description::text) <= 255", name: "transactions_normalized_description_length_check"
    t.check_constraint "occurrence >= 1", name: "transactions_occurrence_check"
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
  add_foreign_key "entries", "budgets"
  add_foreign_key "entries", "categories"
  add_foreign_key "entries_tags", "budgets"
  add_foreign_key "entries_tags", "users"
  add_foreign_key "financial_profiles", "users"
  add_foreign_key "imports", "accounts"
  add_foreign_key "merchant_rules", "categories"
  add_foreign_key "merchant_rules", "users"
  add_foreign_key "tags", "categories"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "imports", column: ["import_id", "account_id"], primary_key: ["id", "account_id"], name: "fk_transactions_import_same_account"
  add_foreign_key "transfer_links", "transactions", column: "inflow_transaction_id"
  add_foreign_key "transfer_links", "transactions", column: "outflow_transaction_id"
  add_foreign_key "transfer_links", "users"
end
