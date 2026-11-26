# frozen_string_literal: true

require "test_helper"

# S3: the shared ownership matrix. The caller is users(:one) (default test
# token); every row targets users(:two)'s data, or tries to inject it, and must
# get the expected status and change nothing.
#
# Every new resource (DM-2 accounts, T1/I2 transactions, OB1, G1, ...) adds
# its rows to ROWS.
class OwnershipMatrixTest < ActionDispatch::IntegrationTest
  # name => [http_method, path (instance_exec'd), params, expected_status]
  ROWS = {
    # --- users (S2) -----------------------------------------------------------
    "users#show other"           => [:get,    -> { api_v1_user_url(users(:two)) }, nil, :not_found],
    "users#update other"         => [:patch,  -> { api_v1_user_url(users(:two)) }, { user: { first_name: "X" } }, :not_found],
    "users#destroy other"        => [:delete, -> { api_v1_user_url(users(:two)) }, nil, :not_found],
    "users#show_by_email other"  => [:get,    -> { show_by_email_api_v1_users_url(email: users(:two).email) }, nil, :not_found],

    # --- budgets (S3-L) ---------------------------------------------------------
    "budgets#show other"         => [:get,    -> { api_v1_budget_url(budgets(:two)) }, nil, :not_found],
    "budgets#update other"       => [:patch,  -> { api_v1_budget_url(budgets(:two)) }, { budget: { name: "X" } }, :not_found],
    "budgets#destroy other"      => [:delete, -> { api_v1_budget_url(budgets(:two)) }, nil, :not_found],

    # --- entries (S3-L) ---------------------------------------------------------
    "entries#show other"         => [:get,    -> { api_v1_entry_url(entries(:two)) }, nil, :not_found],
    "entries#update other"       => [:patch,  -> { api_v1_entry_url(entries(:two)) }, { entry: { amount: 1 } }, :not_found],
    "entries#destroy other"      => [:delete, -> { api_v1_entry_url(entries(:two)) }, nil, :not_found],
    "entries#create in other's budget" =>
                                    [:post,   -> { api_v1_entries_url }, -> { { entry: { budget_id: budgets(:two).id, amount: 1 } } }, :not_found],
    "entries#update moving own entry into other's budget" =>
                                    [:patch,  -> { api_v1_entry_url(entries(:one)) }, -> { { entry: { budget_id: budgets(:two).id } } }, :not_found],
    "entries#create with other's tag" =>
                                    [:post,   -> { api_v1_entries_url }, -> { { entry: { budget_id: budgets(:one).id, amount: 1, tag_ids: [tags(:two).id] } } }, :unprocessable_entity],
    "entries#create with unknown category" =>
                                    [:post,   -> { api_v1_entries_url }, -> { { entry: { budget_id: budgets(:one).id, amount: 1, category_id: 0 } } }, :unprocessable_entity],
    "entries#by_budget for other's budget" =>
                                    [:get,    -> { entries_by_budget_with_default_categories_api_v1_entries_url(budget_id: budgets(:two).id, category_id: categories(:expense).id) }, nil, :not_found],

    # --- tags (S3-L) ----------------------------------------------------------
    "tags#show other"            => [:get,    -> { api_v1_tag_url(tags(:two)) }, nil, :not_found],
    "tags#update other"          => [:patch,  -> { api_v1_tag_url(tags(:two)) }, { tag: { name: "X" } }, :not_found],
    "tags#destroy other"         => [:delete, -> { api_v1_tag_url(tags(:two)) }, nil, :not_found],

    # --- accounts (DM-2) ---------------------------------------------------------
    "accounts#show other"        => [:get,    -> { api_v1_account_url(accounts(:two_checking)) }, nil, :not_found],
    "accounts#update other"      => [:patch,  -> { api_v1_account_url(accounts(:two_checking)) }, { account: { name: "X" } }, :not_found],
    "accounts#destroy other"     => [:delete, -> { api_v1_account_url(accounts(:two_checking)) }, nil, :not_found],

    # --- imports and transactions (I2) -------------------------------------------
    "imports#create into other's account" =>
                                    [:post,   -> { api_v1_account_imports_url(accounts(:two_checking)) }, nil, :not_found],
    "transactions#index for other's account" =>
                                    [:get,    -> { api_v1_transactions_url(account_id: accounts(:two_checking).id) }, nil, :not_found],
    "transactions#index for other's import" =>
                                    [:get,    -> { api_v1_transactions_url(import_id: imports(:two_nov).id) }, nil, :not_found],
    "transactions#update other"  => [:patch,  -> { api_v1_transaction_url(transactions(:two_coffee)) }, { transaction: { category: nil } }, :not_found],
    "transactions#destroy other" => [:delete, -> { api_v1_transaction_url(transactions(:two_coffee)) }, nil, :not_found],
    "transactions#update with unknown category" =>
                                    [:patch,  -> { api_v1_transaction_url(transactions(:one_coffee)) }, { transaction: { category: "no-such-slug" } }, :unprocessable_entity],

    # --- categories: global, read-only (S3-L) -----------------------------------
    "categories#create"          => [:post,   -> { api_v1_categories_url }, { category: { name: "X" } }, :forbidden],
    "categories#update"          => [:patch,  -> { api_v1_category_url(categories(:expense)) }, { category: { name: "X" } }, :forbidden],
    "categories#destroy"         => [:delete, -> { api_v1_category_url(categories(:expense)) }, nil, :forbidden]
  }.freeze

  # A fingerprint of everything the rows could touch.
  def snapshot
    [User, Budget, Entry, Tag, Category, Account, Import, Transaction, MerchantRule].to_h do |model|
      [model.name, model.order(:id).map { |r| r.attributes.except("updated_at") }]
    end.merge("EntriesTags" => Entry.order(:id).map { |e| e.tag_ids.sort })
  end

  ROWS.each do |name, (verb, path, params, status)|
    test "#{name} -> #{status} and changes nothing" do
      before = snapshot
      body = params.respond_to?(:call) ? instance_exec(&params) : params
      public_send(verb, instance_exec(&path), params: body, headers: auth_headers, as: :json)

      assert_response status
      assert_equal before, snapshot
    end
  end

  # --- lists never include other users' records --------------------------------

  test "index endpoints list only the caller's records" do
    get api_v1_budgets_url, headers: auth_headers, as: :json
    assert_equal [budgets(:one).id], response.parsed_body.map { |b| b["id"] }

    get api_v1_entries_url, headers: auth_headers, as: :json
    assert_equal [entries(:one).id], response.parsed_body.map { |e| e["id"] }

    get api_v1_tags_url, headers: auth_headers, as: :json
    assert_not_includes response.parsed_body.map { |t| t["id"] }, tags(:two).id

    get api_v1_users_url, headers: auth_headers, as: :json
    assert_equal [users(:one).id], response.parsed_body.map { |u| u["id"] }

    get api_v1_accounts_url(include_archived: true), headers: auth_headers, as: :json
    assert_equal [accounts(:one_checking).id], response.parsed_body.map { |a| a["id"] }

    get api_v1_transactions_url, headers: auth_headers, as: :json
    assert_equal [transactions(:one_coffee).id], response.parsed_body["transactions"].map { |t| t["id"] }
  end

  # --- injected owner ids are ignored ---------------------------------------------

  test "an injected user_id on budget create is ignored" do
    post api_v1_budgets_url, params: { budget: { name: "Mine", user_id: users(:two).id } }, headers: auth_headers, as: :json

    assert_response :created
    assert_equal users(:one).id, Budget.find(response.parsed_body["id"]).user_id
  end

  test "the caller can still use their own budget, entries and tags" do
    post api_v1_entries_url,
         params: { entry: { budget_id: budgets(:one).id, amount: 5, tag_ids: [tags(:one).id, tags(:global).id] } },
         headers: auth_headers, as: :json
    assert_response :created
    assert_equal [tags(:one).id, tags(:global).id].sort, response.parsed_body["tags"].map { |t| t["id"] }.sort

    get entries_by_budget_with_default_categories_api_v1_entries_url(budget_id: budgets(:one).id, category_id: categories(:expense).id),
        headers: auth_headers, as: :json
    assert_response :success
    assert_equal 1, response.parsed_body.size
  end

  test "a valid token without a provisioned user gets 403 on every scoped resource" do
    headers = auth_headers("sub" => "kp_not_provisioned")
    [api_v1_budgets_url, api_v1_entries_url, api_v1_tags_url, api_v1_users_url, api_v1_accounts_url,
     api_v1_transactions_url].each do |url|
      get url, headers: headers, as: :json
      assert_response :forbidden, url
    end
  end

  test "categories stay readable" do
    get api_v1_categories_url, headers: auth_headers, as: :json
    assert_response :success
    get default_api_v1_categories_url, headers: auth_headers, as: :json
    assert_equal [categories(:expense).id], response.parsed_body.map { |c| c["id"] }
  end
end
