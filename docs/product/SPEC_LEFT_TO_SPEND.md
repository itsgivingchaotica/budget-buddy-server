# Spec — "Left to spend this week" and the Home outlook

**Status:** APPROVED by product owner (2026-11-24). **Amended 2026-11-26 (owner approved, D-028):** §2, §3.2, §4.2; worked examples 10–11; decision 4.
**Phase:** 5, requirements
**Implements:** D-003, D-018 amendment 2, D-021, C-1; plan task **W1** (`WeeklyOutlook`, `GET /outlook/week`), plus the "mark paid" part of **OB1**

---

## 1. Purpose

Answer the lapsed budgeter's daily question on the Home tab: **"How much can I still spend on everyday things this week, and what's coming up?"** The number must be deterministic, explainable in one sentence, honest about data freshness, and need no bank balance (C-1).

## 2. Definitions

| Term | Definition |
|---|---|
| **Today** | The current date in the user's time zone (`financial_profiles.time_zone`, default: device time zone sent at onboarding) (PO-12) |
| **This week** | The 7-day block starting on the most recent `week_starts_on` day (default Monday) on or before today (PO-12) |
| **Flexible category** | An active spending category whose label `fixed_variable = variable`. Default labels in §7 |
| **Monthly budget** | The `category_budgets` row in effect for that category and month (`effective_from` ≤ first of month, latest wins) |
| **Data through** | For each non-archived account with at least one import: the latest `posted_on`. The outlook's `data_through` is the **earliest** of those dates, so no account's missing days are hidden |
| **Flexible spending** | Per flexible category, net money out (refunds reduce it, never below $0), plus **money out only** on uncategorized rows (§4.2), in the window, from non-archived accounts, excluding Transfers and Income |

## 3. Formula

All money math in `BigDecimal`, cents precision; rounding only for display (§5). The figures come from the shared spending analytics service (AN1), so Home, Plan and the coach use the same rules.

### 3.1 Weekly allowance

For each day `d` in this week, and each flexible category `c` with a monthly budget `B(c, month(d))`:

```
daily_rate(c, d) = B(c, month(d)) / days_in_month(month(d))
allowance        = Σ_d Σ_c daily_rate(c, d)
```

A week that crosses a month boundary takes each day's share from the right month, and a budget change effective next month applies from that month's first day.

### 3.2 Spent so far (amended 2026-11-26)

```
window_end = min(today, data_through)
rows       = transactions where week_start ≤ posted_on ≤ window_end
             and account not archived, excluding confirmed transfers

spent_c        = max(0, − Σ amount)              over rows in flexible category c
uncategorized  = Σ (− amount)                    over uncategorized rows with amount < 0
spent          = Σ_c spent_c + uncategorized
```

- **Refunds** (positive amounts in a flexible category) reduce that category's spending, but a category never goes below $0, so a refund in one category can't offset spending in another.
- **Uncategorized money coming in is ignored** until it's categorized: it could be pay or a refund, and counting it would hide spending (§4.2).

### 3.3 Result

```
left = allowance − spent
```

`left` may be negative (overspent).

## 4. Rules and edge cases

### 4.1 States and precedence

The response has exactly one `state`, chosen in this order:

1. **`no_plan`**: no flexible category budgets for any day this week. No number; call to action "Make a plan with your coach".
2. **`stale`**: `today − data_through > 7 days`. Allowance shown; message and "Import new transactions" action.
3. **`no_data_this_week`**: `data_through < week_start`. Full allowance shown; message "No transactions imported for this week yet."
4. **`ok`**: otherwise. If `data_through < today`, also show "Spending counted through <date>."

The response always includes `data_through`.

### 4.2 Uncategorized transactions (amended 2026-11-26)

Rows with no category (waiting for review) count as flexible spending **when money goes out**, so the number errs on the safe side. **Money coming in on an uncategorized row is not counted** until the row is categorized, because it could be a paycheck that would otherwise cancel out real spending. The response reports `uncategorized_count` (all uncategorized rows in the window, in and out), shown as "Includes N transactions to review".

### 4.3 Excluded

Transfers (confirmed transfer links), Income, fixed categories, archived accounts, rows dated after today.

### 4.4 Budget of zero

A flexible category budgeted at $0 adds nothing to the allowance; spending in it still counts.

## 5. Display

| Element | Shown |
|---|---|
| Section label | "**Left to spend · Mon–Sun**" (the user's actual week days) |
| `left ≥ 0` | "**$63** left" (whole dollars, **rounded down**) |
| `left < 0` | "**$0** left · over by **$22**" (overage **rounded up**), Ember colour **with** a warning icon and text label |
| Under the number | "of $149 for the week" (allowance, rounded down) and a progress bar of spent / allowance |
| Detail sheet (tap) | Per-category allowance, spent and left; the assumptions in §6; data-through date |
| Bills section label | "**Bills · next 7 days**" (D-021) |

Rounding is conservative: the user never sees more available than there is.

## 6. Assumptions returned with every result

1. "Only everyday (flexible) categories count; bills are listed separately."
2. "Weekly share = your monthly budget spread evenly across the days of the month."
3. "Based on transactions imported through <date>."
4. If applicable: "Includes N uncategorized transactions; money coming in isn't counted until it's categorized."

## 7. Default category labels (flexible vs fixed)

| Flexible (`variable`) | Fixed (`fixed`) |
|---|---|
| Groceries, Dining Out, Entertainment, Transportation, Healthcare, Clothing, Personal Care, Gifts, Travel, Home Improvement, Other | Rent, Utilities, Subscriptions, Insurance, Debt Payments, Education |

Labels are global defaults, read-only in the MVP (PO-7).

## 8. The rest of the Home outlook

### 8.1 Bills due (obligations)

- **Window (D-021):** rolling **next 7 days**, today through today + 6, deliberately different from the calendar week so a bill due right after the week ends is never a surprise. Plus **unpaid occurrences earlier this week**, flagged "Was due <date>, mark paid if done".
- Due dates come from `RecurrenceSchedule` (plan OB1).
- **Mark paid** (MVP, manual): one record per obligation **occurrence** (obligation + due date), with `paid_on`. Built in OB1 as `obligation_payments`, unique `(obligation_id, due_on)`; un-marking deletes the row.
- Bills are **not subtracted** from Left to spend.

### 8.2 Goal contributions this week

- For each **active, dated** upcoming-payment or purchase goal: `needed_this_week = GoalCalculator.needed_per_week`; `set_aside_this_week` = contributions dated this week; show the remainder ("$25 more toward Car insurance this week").
- **Debt goals** aren't listed here; their monthly payment is an obligation.
- **Undated goals** (e.g. emergency fund) aren't listed in the MVP; a weekly target for them comes in v1.

## 9. API contract

`GET /api/v1/outlook/week` (authenticated, scoped to `current_user`; no parameters in the MVP)

```json
{
  "state": "ok | no_plan | stale | no_data_this_week",
  "today": "2026-11-22",
  "week": { "start": "2026-11-16", "end": "2026-11-22" },
  "data_through": "2026-11-21",
  "left_to_spend": {
    "allowance": "149.33",
    "spent": "85.60",
    "left": "63.73",
    "uncategorized_count": 0,
    "by_category": [
      { "category": "groceries", "allowance": "93.33", "spent": "62.10", "left": "31.23" }
    ]
  },
  "bills_due": {
    "window": { "start": "2026-11-22", "end": "2026-11-28" },
    "items": [
      { "obligation_id": 12, "name": "Rent", "amount": "1200.00", "due_on": "2026-11-23", "paid": false, "overdue": false }
    ]
  },
  "goal_contributions": [
    { "goal_id": 3, "name": "Car insurance", "needed_this_week": "25.00", "set_aside_this_week": "0.00" }
  ],
  "assumptions": ["…"]
}
```

Money as strings (exact decimals). Display rounding happens in the client per §5, using one shared helper. (Example values are illustrative; real API values and slugs win.)

## 10. Worked examples (acceptance tests)

Illustrative data, not real figures.

1. **Normal week.** Week Mon 2026-11-16 → Sun 2026-11-22 (November, 30 days). Flexible budgets: Groceries $400, Dining Out $150, Entertainment $90 (total $640). Allowance = 7 × 640 / 30 = **$149.33**. Spent: Groceries $62.10 + Dining Out $23.50 = **$85.60**. Left = **$63.73** → shown "**$63** left · of $149".
2. **Week crosses a month, budget changes.** Week Mon 2026-11-30 → Sun 2026-12-06. November flexible total $640; an approved plan makes December's total $700. Allowance = 1 × 640/30 + 6 × 700/31 = 21.3333 + 135.4839 = **$156.82**.
3. **Overspent.** Allowance $149.33; spent $171.00 → left −$21.67 → shown "**$0** left · over by **$22**" with warning icon and label.
4. **Refund.** Spent $40.00 at a store, $15.00 refunded in the same flexible category the same week → spent **$25.00**.
5. **Transfer excluded.** $200 moved Checking → Savings, confirmed transfer → contributes **$0** to spent.
6. **Stale data.** Today 2026-11-22, data_through 2026-11-10 → state **`stale`** (takes precedence over `no_data_this_week`); allowance shown, spent $0, import message.
7. **Uncategorized.** One uncategorized −$18.00 this week → spent includes $18.00, `uncategorized_count = 1`.
8. **No plan.** No flexible category budgets → state `no_plan`, no number.
9. **Bills window.** Today Sat 2026-11-21, week Mon 11-16 → Sun 11-22. Rent due Mon 11-23 **appears** in bills (window 11-21 → 11-27). An unpaid phone bill due Tue 11-17 appears with `overdue: true`.
10. **Uncategorized money in (added 2026-11-26).** This week: Groceries −$40.00, an uncategorized −$18.00, and an uncategorized **+$500.00** deposit (a paycheck not yet categorized). Spent = 40.00 + 18.00 = **$58.00** (the deposit is ignored, not netted to $0); `uncategorized_count = 2`.
11. **Refund in another category (added 2026-11-26).** This week: Groceries −$40.00 and a Clothing refund +$60.00 with no Clothing spending. Clothing's spending floors at $0, so spent = **$40.00** (the refund doesn't offset Groceries).

## 11. Out of scope (v1)

Balance-based "safe to spend"; expected income in the calculation; automatic matching of bills to transactions; pace indicator; day-by-day forecast; weekly targets for undated goals; per-user label overrides; a "coming up next week" peek (alternative C, if the two windows confuse people in testing).

## 12. Decisions

1. Uncategorized rows count as spending: **agreed** (2026-11-24); refined by decision 4.
2. Default flexible/fixed split (§7): **accepted** (2026-11-24).
3. Bills window: **Option A**, rolling next 7 days, with explicit labels (D-021) (2026-11-24).
4. **Uncategorized money coming in isn't counted, and each category floors at $0 separately** (owner, 2026-11-26, D-028): raised by Claude Code during AN1; the original §3.2 would have let an uncategorized paycheck cancel out a week's spending.
