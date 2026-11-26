require "test_helper"

# G1 (goals): the endpoints. "Today" is 2026-11-26 (UTC).
class GoalsTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.utc(2026, 11, 26, 12) }
  teardown { travel_back }

  def call(verb, url, params = nil)
    public_send(verb, url, params:, headers: auth_headers, as: :json)
    response.parsed_body
  end

  def goal(**attrs) = users(:one).goals.create!({ goal_type: "purchase", name: "Fund", target_amount: "1000" }.merge(attrs))

  test "POST creates each type; owner and source never come from the body" do
    body = call(:post, api_v1_goals_url, { goal_type: "upcoming_payment", name: "Car insurance", target_amount: "600",
                                           target_date: "2027-03-01", starting_balance: "50", user_id: users(:two).id, source: "coach" })
    assert_response :created
    assert_equal({ "goal_type" => "upcoming_payment", "status" => "active", "source" => "user", "target_amount" => "600.00",
                   "target_date" => "2027-03-01", "saved" => "50.00", "balance" => nil, "remaining" => "550.00" },
                 body.slice("goal_type", "status", "source", "target_amount", "target_date", "saved", "balance", "remaining"))
    assert_equal users(:one).id, Goal.find(body["id"]).user_id

    body = call(:post, api_v1_goals_url, { goal_type: "debt_payoff", name: "Card", starting_balance: "1840", apr: "22.9", monthly_payment: "120" })
    assert_response :created
    assert_equal ["1840.00", "22.90", "120.00", nil, "1840.00"], body.values_at("balance", "apr", "monthly_payment", "saved", "remaining")

    body = call(:post, api_v1_goals_url, { goal_type: "purchase", name: "Emergency fund", target_amount: "2000" })
    assert_response :created
    assert_nil body["target_date"]

    call(:post, api_v1_goals_url, { goal_type: "debt_payoff", name: "Card", starting_balance: "1840" })
    assert_response :unprocessable_entity
    assert_equal %w[apr monthly_payment], response.parsed_body["errors"].keys.sort
  end

  test "GET lists active goals: dated by date, then undated, then debt" do
    goal(name: "Undated")
    goal(goal_type: "debt_payoff", name: "Card", target_amount: nil, starting_balance: "900", apr: "20", monthly_payment: "50")
    goal(goal_type: "upcoming_payment", name: "Later", target_date: Date.new(2027, 6, 1))
    goal(name: "Sooner", target_date: Date.new(2027, 1, 1))
    goal(name: "Done", status: "completed")
    assert_equal %w[Sooner Later Undated Card], call(:get, api_v1_goals_url)["goals"].map { |g| g["name"] }
    assert_equal %w[Done], call(:get, api_v1_goals_url(status: "completed"))["goals"].map { |g| g["name"] }
    assert_equal 5, call(:get, api_v1_goals_url(status: "all"))["goals"].size
    call(:get, api_v1_goals_url(status: "paused"))
    assert_response :unprocessable_entity
  end

  test "set aside, then undo; the goal comes back updated each time" do
    g = goal
    body = call(:post, contributions_api_v1_goal_url(g), { amount: "62", note: " first week " })
    assert_response :created
    assert_equal({ "kind" => "set_aside", "amount" => "62.00", "balance_after" => nil, "contributed_on" => "2026-11-26", "note" => "first week" },
                 body["contribution"].slice("kind", "amount", "balance_after", "contributed_on", "note"))
    assert_equal ["62.00", "938.00"], body["goal"].values_at("saved", "remaining")
    cid = body["contribution"]["id"]
    assert_equal [cid], call(:get, api_v1_goal_url(g))["contributions"].map { |c| c["id"] }

    body = call(:delete, contribution_api_v1_goal_url(g, contribution_id: cid))
    assert_response :success
    assert_equal "0.00", body["goal"]["saved"]
    call(:delete, contribution_api_v1_goal_url(g, contribution_id: cid))
    assert_response :not_found
  end

  test "update balance on a debt; wrong kinds, future dates and bad dates are refused" do
    d = goal(goal_type: "debt_payoff", name: "Card", target_amount: nil, starting_balance: "1840", apr: "22.9", monthly_payment: "120")
    body = call(:post, contributions_api_v1_goal_url(d), { balance_after: "1720", contributed_on: "2026-11-20" })
    assert_response :created
    assert_equal ["balance_update", "1720.00"], [body["contribution"]["kind"], body["goal"]["balance"]]

    call(:post, contributions_api_v1_goal_url(d), { kind: "set_aside", amount: "10" })
    assert_response :unprocessable_entity
    call(:post, contributions_api_v1_goal_url(d), { balance_after: "1700", contributed_on: "2026-11-27" })
    assert_response :unprocessable_entity
    call(:post, contributions_api_v1_goal_url(d), { balance_after: "1700", contributed_on: "next week" })
    assert_equal "contributed_on", response.parsed_body["field"]
    assert_equal 1, d.contributions.count
  end

  test "PATCH edits fields and status, never the type; archived goals take no new contributions" do
    g = goal
    body = call(:patch, api_v1_goal_url(g), { name: "Rainy day", target_amount: "1500", goal_type: "debt_payoff" })
    assert_response :success
    assert_equal ["Rainy day", "1500.00", "purchase"], body.values_at("name", "target_amount", "goal_type")
    call(:patch, api_v1_goal_url(g), { target_amount: "0" })
    assert_response :unprocessable_entity

    call(:patch, api_v1_goal_url(g), { status: "archived" })
    assert_response :success
    assert_empty call(:get, api_v1_goals_url)["goals"]
    call(:post, contributions_api_v1_goal_url(g), { amount: "5" })
    assert_response :unprocessable_entity
  end

  test "another user's contribution can't be undone through my own goal" do
    mine = goal
    assert_no_difference -> { GoalContribution.count } do
      call(:delete, contribution_api_v1_goal_url(mine, contribution_id: goal_contributions(:two_trip_first).id))
    end
    assert_response :not_found
  end

  # G2: every figure on a card comes from the API, money as strings.
  test "GET /goals carries the G2 progress: saving and debt, with the what-if step" do
    users(:one).goals.create!(goal_type: "upcoming_payment", name: "Insurance", target_amount: "620",
                              target_date: Date.new(2027, 1, 10), created_at: Time.utc(2026, 11, 25, 12))
    users(:one).goals.create!(goal_type: "debt_payoff", name: "Card", starting_balance: "5000", apr: "22", monthly_payment: "200",
                              created_at: Time.utc(2026, 11, 10, 12))
    saving, debt = call(:get, api_v1_goals_url)["goals"].map { |g| g["progress"] }
    assert_equal({ "kind" => "saving", "weeks_left" => 7, "needed_per_week" => "88.58", "still_needed_this_week" => "88.58",
                   "on_track" => true, "percent" => 0, "remaining" => "620.00" },
                 saving.slice("kind", "weeks_left", "needed_per_week", "still_needed_this_week", "on_track", "percent", "remaining"))
    # 88.58 by Sun 11-29 is short of 155; 177.16 by Sun 12-06 crosses it
    assert_equal({ "percent" => 25, "amount" => "155.00", "reached" => false, "reached_on" => nil, "projected_on" => "2026-12-06" },
                 saving["milestones"].first)
    assert_equal "91.67", debt["interest_this_month"]
    assert_equal({ "never_pays_off" => false, "months" => 34, "payoff_month" => "2029-09", "total_interest" => "1749.90" }, debt["payoff"])
    assert_equal ["50.00", "464.19", 8], debt["what_if"].values_at("extra", "interest_saved", "months_sooner")
    assert debt["assumptions"].any?

    what_if = call(:get, api_v1_goals_url(what_if_extra: "100"))["goals"].last["progress"]["what_if"]
    assert_equal "100.00", what_if["extra"]
    call(:get, api_v1_goals_url(what_if_extra: "-5"))
    assert_equal "what_if_extra", response.parsed_body["field"]
    call(:get, api_v1_goals_url(what_if_extra: "lots"))
    assert_response :unprocessable_entity
  end
end
