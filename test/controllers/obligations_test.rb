require "test_helper"

# OB1 (bills): the endpoints. "Today" is Sat 2026-11-21 (UTC) unless set.
class ObligationsTest < ActionDispatch::IntegrationTest
  setup do
    @rent = Category.create!(name: "Rent", slug: "rent", kind: "spending", fixed_variable: "fixed", active: true, position: 1)
    @phone = Category.create!(name: "Utilities", slug: "utilities", kind: "spending", fixed_variable: "fixed", active: true, position: 2)
    @groceries = Category.create!(name: "Groceries", slug: "groceries", kind: "spending", fixed_variable: "variable", active: true, position: 3)
    travel_to Time.utc(2026, 11, 21, 12)
  end

  teardown { travel_back }

  def call(verb, url, params = nil)
    public_send(verb, url, params:, headers: auth_headers, as: :json)
    response.parsed_body
  end

  def bill(name, amount, first, recurrence = "monthly", **attrs)
    users(:one).obligations.create!(name:, amount:, category: @rent, first_due_on: Date.parse(first), recurrence:, **attrs)
  end

  test "POST creates a bill from a slug, with its day and current occurrence" do
    body = call(:post, api_v1_obligations_url, { name: "Rent", amount: "1200", category: "rent", first_due_on: "2026-11-30",
                                                  recurrence: "monthly", day_of_month: 31, account_id: accounts(:one_checking).id,
                                                  source: "coach", user_id: users(:two).id })
    assert_response :created
    ob = Obligation.find(body["id"])
    assert_equal [users(:one).id, "user", 31, accounts(:one_checking).id], [ob.user_id, ob.source, ob.day_of_month, ob.account_id],
                 "owner and source are never taken from the body"
    assert_equal({ "due_on" => "2026-11-30", "status" => "due", "paid_on" => nil }, body["current"])
    assert_equal "1200.00", body["amount"]
    assert_equal "2026-11-30", body["next_due_on"]
  end

  test "POST refuses flexible or unknown categories, and bad schedules" do
    call(:post, api_v1_obligations_url, { name: "Food", amount: "50", category: "groceries", first_due_on: "2026-12-01", recurrence: "monthly" })
    assert_response :unprocessable_entity
    call(:post, api_v1_obligations_url, { name: "X", amount: "50", category: "nope", first_due_on: "2026-12-01" })
    assert_equal ["invalid_reference", "category"], response.parsed_body.values_at("error", "field")
    call(:post, api_v1_obligations_url, { name: "X", amount: "50", category: "rent", first_due_on: "2026-12-01", recurrence: "daily" })
    assert_response :unprocessable_entity
    assert_equal 0, Obligation.where(user: users(:one)).count
  end

  test "GET /obligations: summary, status chips and only active bills" do
    bill("Rent", "1200", "2026-01-23")                 # due Mon 11-23: in the 7 days
    phone = bill("Phone", "45", "2026-01-17")          # due Tue 11-17: past, unpaid
    paid = bill("Internet", "60", "2026-01-19")        # due 11-19, paid
    paid.payments.create!(due_on: Date.new(2026, 11, 19), paid_on: Date.new(2026, 11, 18))
    bill("Insurance", "600", "2027-03-01", "yearly")   # first one later
    bill("Old", "10", "2026-01-01").archive!
    body = call(:get, api_v1_obligations_url)
    assert_response :success
    assert_equal({ "start" => "2026-11-21", "end" => "2026-11-27" }, body["window"])
    # 1200 + 45 + 60 + 600/12 = 1355.00; due in the 7 days and unpaid: Rent only
    assert_equal({ "monthly_total" => "1355.00", "due_in_next_7_days" => 1 }, body["summary"])
    chips = body["obligations"].to_h { |o| [o["name"], o["current"].values_at("due_on", "status")] }
    assert_equal({ "Insurance" => ["2027-03-01", "due"], "Internet" => ["2026-11-19", "paid"],
                   "Phone" => ["2026-11-17", "was_due"], "Rent" => ["2026-11-23", "due_soon"] }, chips)
    assert_equal "2026-12-17", body["obligations"].find { |o| o["id"] == phone.id }["next_due_on"]
    assert body["assumptions"].any?
  end

  test "mark paid twice makes one row; unmark restores due; dates are checked" do
    ob = bill("Rent", "1200", "2026-01-23")
    url = payments_api_v1_obligation_url(ob)
    body = call(:post, url, { due_on: "2026-11-23" })
    assert_response :created
    assert_equal({ "obligation_id" => ob.id, "due_on" => "2026-11-23", "paid_on" => "2026-11-21", "paid" => true }, body)
    call(:post, url, { due_on: "2026-11-23", paid_on: "2026-11-20" })
    assert_response :ok
    assert_equal [[Date.new(2026, 11, 23), Date.new(2026, 11, 21)]], ob.payments.pluck(:due_on, :paid_on), "first mark wins"
    assert_equal "paid", call(:get, api_v1_obligation_url(ob))["current"]["status"]

    call(:delete, payment_api_v1_obligation_url(ob, due_on: "2026-11-23"))
    assert_response :no_content
    assert_equal "due_soon", call(:get, api_v1_obligation_url(ob))["current"]["status"]
    call(:delete, payment_api_v1_obligation_url(ob, due_on: "2026-11-23"))
    assert_response :no_content, "unmarking again is harmless"

    call(:post, url, { due_on: "2026-11-24" })
    assert_response :unprocessable_entity, "not a due date of this bill"
    call(:post, url, { due_on: "2026-11-23", paid_on: "2026-11-22" })
    assert_response :unprocessable_entity, "paid in the future"
    call(:post, url, { due_on: "soon" })
    assert_equal "due_on", response.parsed_body["field"]
    assert_equal 0, ob.payments.count
  end

  test "paid_on defaults to today in the user's time zone" do
    FinancialProfile.find_or_create_by!(user: users(:one)).update!(time_zone: "Pacific/Auckland") # already Sun 11-22 there
    ob = bill("Rent", "1200", "2026-01-23")
    assert_equal "2026-11-22", call(:post, payments_api_v1_obligation_url(ob), { due_on: "2026-11-23" })["paid_on"]
    assert_equal "2026-11-22", call(:post, payments_api_v1_obligation_url(ob), { due_on: "2026-12-23", paid_on: "2026-11-22" })["paid_on"]
  end

  test "GET /obligations/due lists every occurrence in the range with paid" do
    rent = bill("Rent", "1200", "2026-01-23")
    bill("Gym", "10", "2026-11-06", "weekly")
    bill("Old", "5", "2026-11-20", "weekly").archive!
    rent.payments.create!(due_on: Date.new(2026, 11, 23), paid_on: Date.new(2026, 11, 20))
    body = call(:get, due_api_v1_obligations_url(from: "2026-11-16", to: "2026-11-27"))
    assert_response :success
    assert_equal [["Gym", "2026-11-20", false], ["Rent", "2026-11-23", true], ["Gym", "2026-11-27", false]],
                 body["items"].map { |i| i.values_at("name", "due_on", "paid") }
    assert_equal "1200.00", body["items"][1]["amount"]

    call(:get, due_api_v1_obligations_url(from: "2026-11-27", to: "2026-11-16"))
    assert_response :unprocessable_entity
    call(:get, due_api_v1_obligations_url(from: "2026-01-01", to: "2027-01-02"))
    assert_response :unprocessable_entity, "more than 366 days"
    call(:get, due_api_v1_obligations_url(from: "2026-11-16"))
    assert_response :unprocessable_entity
  end

  test "PATCH edits a bill; archive hides it and stops edits and payments" do
    ob = bill("Rent", "1200", "2026-01-23")
    body = call(:patch, api_v1_obligation_url(ob), { amount: "1250.50", category: "utilities", account_id: nil })
    assert_response :success
    assert_equal ["1250.50", "utilities"], body.values_at("amount", "category")

    call(:patch, api_v1_obligation_url(ob), { recurrence: "weekly" })
    assert_response :success
    assert_nil ob.reload.day_of_month

    body = call(:post, archive_api_v1_obligation_url(ob))
    assert_response :success
    assert body["archived_at"].present?
    assert_nil body["current"]
    assert_empty call(:get, api_v1_obligations_url)["obligations"]
    call(:patch, api_v1_obligation_url(ob), { amount: "1" })
    assert_response :unprocessable_entity
    call(:post, payments_api_v1_obligation_url(ob), { due_on: "2026-11-27" })
    assert_response :unprocessable_entity
  end
end
