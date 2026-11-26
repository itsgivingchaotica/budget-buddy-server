# AN1: one user's hand-made history, shared by the analytics tests. "Today"
# is Thu 2026-11-26 (UTC). users(:one)'s fixture row (Fixture Coffee,
# Oct 1, -4.50, uncategorized) is part of it.
#
#   checking (latest row Nov 25)          savings (Nov 6 … Nov 20)
#   Aug  groceries -100 (Aug 1), -300      Nov 6  transfer in +200 (Transfers)
#        dining -50                        Nov 20 income +1
#   Sep  groceries -380, dining -70,
#        rent -1200, income +3000          archived account: groceries -777 Nov 10
#   Oct  rent -1200 (Oct 1), income +3000 (Oct 1), dining -100 (Oct 5),
#        dining refund +20 (Oct 9), groceries -420 (Oct 15)
#   Nov  rent -1200 + income +3000 (Nov 1), groceries -150 (Nov 3),
#        transfer out -200 (Nov 5, Transfers), groceries refund +30 (Nov 10),
#        dining -40 (Nov 12), personal care -25 (Nov 13),
#        uncategorized -18 (Nov 14) and +500 (Nov 15), rent -12 (Nov 25,
#        a late fee), and a groceries row on Nov 28 (future) -999
#
# data_from Aug 1; data_through Nov 20 (the earliest of the accounts' latest
# rows: checking Nov 25, savings Nov 20).
module SpendingScenario
  NOW = Time.utc(2026, 11, 26, 12)

  def build_spending_scenario
    @user = users(:one)
    cat = ->(name, slug, kind, fv = nil, pos = 0) { Category.create!(name:, slug:, kind:, fixed_variable: fv, active: true, position: pos) }
    @groceries = cat.("Groceries", "groceries", "spending", "variable", 1)
    @dining = cat.("Dining Out", "dining-out", "spending", "variable", 2)
    @entertainment = cat.("Entertainment", "entertainment", "spending", "variable", 3)
    @personal = cat.("Personal Care", "personal-care", "spending", "variable", 4)
    @rent = cat.("Rent", "rent", "spending", "fixed", 10)
    @income = cat.("Income", "income", "income", nil, 20)
    @transfers = cat.("Transfers", "transfers", "transfer", nil, 21)

    @checking = accounts(:one_checking)
    @savings = @user.accounts.create!(name: "Savings", kind: "savings", purpose: "savings")
    old = @user.accounts.create!(name: "Old card", kind: "credit_card", purpose: "spending")

    n = 0
    add = lambda do |account, on, amount, category|
      n += 1
      account.transactions.create!(posted_on: Date.parse(on), amount:, description: "ROW #{n}", category:,
                                   categorization_source: category ? "rule" : "none")
    end
    [["2026-08-01", "-100", @groceries], ["2026-08-12", "-300", @groceries], ["2026-08-20", "-50", @dining],
     ["2026-09-01", "3000", @income], ["2026-09-01", "-1200", @rent], ["2026-09-10", "-380", @groceries], ["2026-09-18", "-70", @dining],
     ["2026-10-01", "3000", @income], ["2026-10-01", "-1200", @rent], ["2026-10-05", "-100", @dining],
     ["2026-10-09", "20", @dining], ["2026-10-15", "-420", @groceries],
     ["2026-11-01", "3000", @income], ["2026-11-01", "-1200", @rent], ["2026-11-03", "-150", @groceries],
     ["2026-11-05", "-200", @transfers], ["2026-11-10", "30", @groceries], ["2026-11-12", "-40", @dining],
     ["2026-11-13", "-25", @personal], ["2026-11-14", "-18", nil], ["2026-11-15", "500", nil],
     ["2026-11-25", "-12", @rent], ["2026-11-28", "-999", @groceries]].each { |on, amount, c| add.(@checking, on, amount, c) }
    add.(@savings, "2026-11-06", "200", @transfers)
    add.(@savings, "2026-11-20", "1", @income)
    add.(old, "2026-11-10", "-777", @groceries)
    old.archive!

    @user.category_budgets.create!(category: @groceries, amount: "400", effective_from: Date.new(2026, 10, 1))
    @user.category_budgets.create!(category: @groceries, amount: "130", effective_from: Date.new(2026, 11, 1))
    @user.category_budgets.create!(category: @dining, amount: "35", effective_from: Date.new(2026, 11, 1))
    @user.category_budgets.create!(category: @entertainment, amount: "0", effective_from: Date.new(2026, 11, 1))
  end
end
