# Screen spec — Plan tab (C8 plan tab screens)

**Status:** APPROVED by the product owner (2026-11-25), including the whole-month budget-change rule in §6. Milestone 2.
**Visual source:** canvas page "Plan" (Plan · budgets, bills, goals, change a budget). Reference screenshots: `docs/product/screens/Plan-*.png`.
**Depends on:** DM-3 (category budgets), OB1 (bills), G1/G2 (goals and goal maths), AN1/AN2 (spending analytics), PL2 (plan approval). Shared rules (brand, money format, accessibility, errors) as in `SCREENS_ACTIVITY.md`.

---

## 1. Purpose

One place to see the approved plan and how this month is going against it: **budgets** for everyday spending, **bills**, and **goals**. The Budgets section is also the **monthly dashboard** (P9): Home's "Month" switch opens it.

## 2. Structure

- Header: "Your plan", "Approved <date> · with your coach" (from the approved `plan_proposals` row), **Ask coach** button (opens the Coach tab).
- Segmented control: **Budgets · Bills · Goals** (`aria-current` on the active one). Remembers the last section while the app is open.
- **No plan yet** (no category budgets): the whole tab shows the Home "no plan" card ("Let's make a plan together" → coach interview). No segments.

## 3. Budgets (and monthly dashboard)

| Element | Behaviour | API |
|---|---|---|
| Summary card | "Everyday budgets · <Month>", total monthly budget, "$X spent through <data_through>" | `GET /api/v1/analytics/budget_vs_actual?month=YYYY-MM` (AN2) |
| Rows (everyday/flexible categories with a budget) | Name; "$480 /month"; bar = spent / budget (Moss; Ember when over, capped at 100%); "$356 spent"; "$124 left" or "**$6 over**" (Ember-dark, bold, plus the word "over") | same |
| Footnote | "Rent, utilities and other fixed costs are in **Bills**. Tap a budget to change it." | — |
| Month | Current month by default; when opened from Home's Month switch, same view. Previous months: ‹ › arrows beside the month name (read-only) | `month` param |

- **Which budget amount a month uses:** the row in effect on that month's 1st (`effective_from` ≤ 1st, latest).
- Uncategorized spending appears as a last row "Not yet categorized · $X" with a link to Review, so the totals add up.
- All figures come from AN1; the client only formats (whole-dollar display per the shared helper; the summary keeps cents only if the API returns them).

### 3.1 Change a budget (sheet)

| Element | Behaviour |
|---|---|
| Title "<Category> budget", Cancel | — |
| Amount | −/+ buttons in $10 steps (labelled "Decrease by $10" / "Increase by $10"); tapping the amount opens a number keypad; whole dollars; $0–$10,000 |
| Context rows (from the API, not computed in the app) | "About per week" (`amount × 12 / 52`, rounded down), "Your average, last 3 months", "Spent this month" |
| Note | "Applies to all of <Month>, including this week's Left to spend." |
| Save | "Save $X a month" → upsert the budget for **this month** (`effective_from` = 1st of the current month in the user's time zone); returns to Budgets with the new figures |

API: `GET /api/v1/category_budgets/:category_slug/context` (weekly equivalent, 3-month average, spent this month) and `PUT /api/v1/category_budgets/:category_slug` `{ "amount": "200.00" }`. Only flexible categories; fixed categories are edited as bills. Changing a budget doesn't reopen or change the approved plan proposal; it's a normal edit.

## 4. Bills

| Element | Behaviour | API |
|---|---|---|
| Summary card | "Bills each month" total; "N due in the next 7 days" | `GET /api/v1/obligations` |
| Rows | Name; schedule ("Monthly · 23rd", "Every 2 weeks · Fri"); amount; status chip for the current occurrence: **Paid <date>** (Fern), **Due <day, date>** within 7 days (review colours), **Was due <date>** if past and unpaid (Ember text + warning icon), otherwise "Due <date>" (neutral) | same + `obligation_payments` |
| Tap a row | Bill sheet: name, amount, schedule, category (fixed categories only), paid-from account (optional); **Mark paid / Mark unpaid** for the current occurrence; **Archive bill** (confirm; history kept) | `PATCH /obligations/:id`, `POST`/`DELETE /obligations/:id/payments/:due_on`, `POST /obligations/:id/archive` |
| **+ Add a bill** | Same sheet, empty. Schedule options: monthly on day 1–31 (29–31 fall on the month's last day when shorter), weekly, every 2 weeks (from a start date) | `POST /obligations` |

Mark paid here and on Home use the same endpoint and stay in sync.

## 5. Goals

One card per active goal, ordered: dated goals by date, then undated, then debt.

| Goal type | Card shows (all from G2) | Action |
|---|---|---|
| Upcoming payment / purchase (dated) | Name; "Purchase · by <date>"; **On track** / **Behind** chip; saved "of" target; percent; bar; milestone dots 25/50/75/100 (filled when reached); "Set aside **$62 a week** to get there on time." | **Set aside money** → sheet: amount, date (default today), note → `POST /goals/:id/contributions` |
| Undated (e.g. emergency fund) | Same, without the weekly line or status chip | Set aside money |
| Debt payoff | "Debt · 22.9% APR"; chip; "$1,840 left to pay"; percent paid; bar; dots; "Paid off in **<month year>** at $X a month · $Y interest this month"; one what-if line "Paying $50 more a month: paid off **<month year>**, saving **$Z** in interest" | **Update balance** → sheet: new balance, date → `POST /goals/:id/contributions` with `kind: balance_update` |

- Every number on a card is returned by `GET /api/v1/goals` (G2); the app does no maths. The what-if amount ($50) is a fixed MVP step, sent as `what_if_extra=50`.
- Chip colours: On track = Fern/Pine; Behind = review colours, always with the word.
- **No "+ Add goal" in the MVP** (approved): goals are created in onboarding and plan approval. An empty Goals section says "Goals come from your plan. Ask your coach to add one." with a link to the coach interview. "+ Add goal" is v1.
- Undo for "Set aside" and "Update balance": a toast with Undo for 5 seconds (`DELETE /goals/:id/contributions/:cid`).

## 6. Owner choices (2026-11-25)

1. **Editing budgets in the MVP: Approved. Whole-month rule approved 2026-11-25.** Background: I recommended "a change starts this week; earlier weeks keep the old amount". The approved schema stores budgets by month (`category_budgets.effective_from` is always the 1st), so a change can only start at a month boundary. Proposed instead: **a change applies to the whole current month**, including this week's Left to spend. Earlier weeks of the month are recalculated too, but the MVP shows no past weeks, so nothing visible changes. The alternative (any start date) would mean changing an approved table rule and the Left to spend maths, for no visible gain. The canvas sheet now says "Applies to all of <Month>…".
2. **Plan → Budgets is the monthly dashboard (P9): Approved.** Home's Month switch opens it; no separate dashboard screen.
3. **"+ Add a bill" in the MVP; goals only through onboarding, "+ Add goal" in v1: Approved.**

## 7. Acceptance (owner's phone, demo data with an approved plan)

1. Budgets shows each everyday category with budget, spent and left/over; totals equal the Coach's answer for the same month.
2. A category over budget shows "over" in words and colour; uncategorized spending appears as its own row.
3. Changing Dining Out from $180 to $200 updates the row, the summary and Home's Left to spend immediately.
4. Previous-month arrows show last month read-only with that month's budgets.
5. Bills: marking Phone paid here shows it paid on Home, and the reverse.
6. Adding a bill due on the 31st shows the correct due date in a 30-day month.
7. Goals: "Set aside $50" on the car fund updates saved, percent and the weekly line; Undo restores it.
8. Debt: "Update balance" changes the payoff date and interest figures; the figures match `DebtCalculator` tests.
9. With no plan, the tab shows the "Let's make a plan together" card.

**Automated:** request tests for each endpoint (shape + ownership-matrix rows); service tests for the month rule in §3 and the day-29–31 rule in §4; client tests for the chip states and the over-budget row.

## 8. Later (v1)

"+ Add goal"; editing goal targets and dates; budget history chart; weekly targets for undated goals; recurring-bill detection suggestions.
