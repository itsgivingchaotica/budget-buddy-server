# Budget Buddy — Onboarding and plan drafting spec (ON1 onboarding questions, ON2 coach follow-ups, PL1 plan drafting, PL2 plan approval, C5 onboarding screens, C6 plan approval screen)

**Status:** APPROVED by the product owner (2026-11-25), including the four §10 decisions. **Amended 2026-11-28 (owner approved):** §5 threshold (D-030), §6.2, §6.4, §7 (D-032). Milestone 2.
**Builds on:** D-002 (import → interview → coach drafts → user approves; small changes first; AI proposes, Rails calculates, user decides), D-010 (financial profile), D-019 (first run), D-021 (Left to spend), MVP_SCOPE P5–P7 and success criterion 1 (sign-up to approved plan in under 5 minutes), PO-4/PO-5/PO-14.
**Visual source:** canvas page "Home & onboarding" (steps 1–4). Reference screenshots: `docs/product/screens/Onboard-*.png` (to be exported with this spec).
**Depends on:** C2/C2b (accounts, import, review groups), AN1 (spending analytics), OB1 (bills), G1/G2 (goals and goal maths), DM-3 (category budgets).

---

## 1. Purpose and flow

A new user with imported history gets a realistic first plan in about 3 minutes, built from **their own numbers**, with the coach choosing gentle changes and explaining them, and nothing saved until they approve.

```
Home "no plan" ─▶ 1 Accounts and import (Activity flow) ─▶ 2 Interview (5 questions + ≤ 2 follow-ups)
   ─▶ 3 A few uncertain merchants (top 3–5) ─▶ 4 Draft plan ─▶ Approve ─▶ Home
```

- **Entry:** Home's "Make a plan with your coach" (W1 `no_plan` state), Plan tab's no-plan card, and "Continue" on step 1.
- **Resumable:** progress is saved after every answer; leaving and returning resumes at the same step.
- **Step indicator:** "Step N of 4" with a progress bar (as on the canvas).

## 2. Division of work

| Who | Does |
|---|---|
| **Rails** | Works out facts from the data (pay pattern, side income, likely bills, each category's usual spending); computes every candidate figure (budget options, income check, goal maths); validates the model's choices; saves on approval. |
| **Claude** | Phrases up to 2 follow-up questions from a fixed menu (ON2); picks one budget option per category and writes short reasons (PL1). **Never writes a number** (§6.3). |
| **User** | Answers, adjusts anything, approves. |

**Privacy (D-008):** Claude receives category-level figures, answer choices and goal types only. No merchant names, transaction descriptions, account names or dates.

## 3. Step 1: accounts and import

The existing Activity flow (C2), shown inside onboarding with the step header and a **Continue** button (enabled once at least one account has a successful import). No new API.

## 4. Step 2: interview (ON1)

### 4.1 Facts Rails prepares (`Onboarding::Facts`, deterministic)

| Fact | Rule |
|---|---|
| Pay pattern guess | From Income-category rows in the last 90 days on accounts with purpose `spending`/`bills`: the most common gap between deposits ≥ $200 → weekly (6–8 days), every 2 weeks (13–15), twice a month (two clusters per month), monthly (28–31); else irregular. Includes the last pay date. |
| Side income | Monthly median of money in over the last 3 full months on accounts with purpose `side_income` (excluding confirmed transfers); shown only if ≥ $50. |
| Likely bills | Fixed-category money out with the same merchant key in ≥ 2 of the last 3 full months, amounts within ±10%, day of month within ±3 → name (merchant display name, editable), typical amount (median), usual day, category. |
| Usual spending | Per flexible category: median monthly spending over the last up to 6 full months (§6.1). |

### 4.2 The five questions

(The canvas mock-up shows the side-income question before the paycheck question; build them in the order below. The spec is the source of truth.)

Each question shows the coach avatar and a templated sentence that may include **Rails facts** (never model text). Answers are tap-first, with "Type your own answer" only where noted.

| # | Question (template) | Answer | Saved to `financial_profiles` |
|---|---|---|---|
| 1 | "How often does your main paycheck arrive?" Pre-selected from the pay-pattern guess: "Looks like every 2 weeks, last on Fri, Nov 13." | Weekly · Every 2 weeks · Twice a month · Monthly · It varies; plus "Next payday" date (pre-filled) | pay pattern fields (PO-5) |
| 2 | Only if side income was found: "I see about **$410** a month coming into **Venmo**. Is that income from your side job?" | Yes, count it · Sometimes, don't count on it · No, it's not income | `answers.side_income` |
| 3 | "These look like regular bills. Keep the ones that are right." | Checklist of likely bills (name, amount, "monthly on the 23rd"), each editable; "+ Add a bill" | `answers.bills` (become draft obligations) |
| 4 | "What are you saving for or paying down?" | Multi-select: Upcoming payment · Something to buy · Emergency fund · Pay off a debt · Nothing for now; each opens a short form (name, amount, date; debt: balance, APR, monthly payment) | `answers.goals` (become draft goals) |
| 5 | "How big a change feels right?" | Keep things as they are · Small trims (default) · Push me a bit | `answers.change_appetite` |

API: `GET /api/v1/onboarding` (step, facts, saved answers) and `PUT /api/v1/onboarding/answers` (partial updates, validated per question).

## 5. Coach follow-ups (ON2)

After question 5, the coach may ask **at most 2** short follow-ups. To keep this safe and testable, Claude **chooses from a fixed menu of slots** and phrases the question; Rails supplies the answer options and stores the result.

| Slot | Asked when (Rails decides eligibility) | Options (from Rails) | Used by |
|---|---|---|---|
| `irregular_income_floor` | Pay = "It varies" | Amount: "A month I can count on" | income check (§6.2) |
| `biggest_trim_ok` | Appetite ≠ keep and the top everyday category's usual is **≥ 120%** of its lowest recent month (D-030) | Yes · A little · Leave it alone, for the top category | option filter |
| `goal_priority` | Two or more goals | Order the goals | goal order in plan |
| `bill_missing` | No rent/housing bill selected but Rent spending exists | Add it · It's included already · I don't pay rent | bills |
| `side_income_use` | Side income counted | Toward goals · Everyday spending · Both | goal funding note |

**Model call** (structured output): input = eligible slots with one-line descriptions, answers so far (choices only). Output = `{ "follow_ups": [ { "slot": "<eligible slot>", "question": "<≤ 120 chars, no digits>" } ] }` with 0–2 items. Rails rejects unknown or ineligible slots, duplicates, digits, or long text. **Any error, timeout or cap → skip follow-ups silently** and continue; onboarding never blocks on AI.

API: `POST /api/v1/onboarding/follow_ups` → the questions with Rails options; answers via `PUT /onboarding/answers`.

## 6. Plan drafting (PL1)

### 6.1 Candidate budgets (Rails, `PlanCandidates`)

For each flexible category with spending in the period:
- **Usual** = median of monthly spending over the last up to 6 **full** months (the current partial month is excluded; confirmed transfers excluded; uncategorized rows excluded and counted in a note).
- **Options:** `keep` = usual rounded **up** to $5; `trim` = 90% of usual rounded to $5 (only if at least $5 below keep); `stretch` = 80% rounded to $5 (only if appetite = "Push me a bit" and the category isn't essential: Groceries, Healthcare and Transportation never get `stretch`).
- Fewer than 2 full months of data → `keep` only, marked "new".
- Flexible categories with no spending get no budget (can be added later in the Plan tab).

### 6.2 Income check (Rails) (amended 2026-11-28, D-032)

- **Monthly income:**
  - **Regular pay:** the median of the last 3 full months of Income on spending/bills accounts, **unless the user changed the paycheck amount in question 1**; then their amount × paychecks per month (weekly 52/12, every 2 weeks 26/12, twice a month 2, monthly 1), using the **same monthly-average function as bills** (OB1).
  - **Pay "It varies":** the stated floor (`irregular_income_floor`) if the user answered it; otherwise the **lowest** of the last 3 full months, shown as "Based on your lowest recent month".
  - **Plus side income** if the user chose "Yes, count it".
- **Committed** = kept bills (step 3, monthly-averaged with the OB1 function) + dated goals' monthly contributions (G2 weekly need × 52 / 12) + **each debt goal's monthly payment, unless a kept bill is in Debt Payments** (never counted twice).
- **Room for everyday spending** = income − committed.
- Rails sends each option set **plus** `room` to the model. After the model chooses, Rails recomputes the total; the draft records `fits: true/false` and the gap. If the cheapest allowed choices still don't fit, the draft says so honestly (§6.5) rather than inventing cuts.
- **Rent added from a follow-up:** if the user answered `bill_missing` with "Add it", the draft adds a Rent bill at the **median monthly Rent spending of the last 3 full months**, on the usual day, labelled "from your spending" and editable on the draft.

### 6.3 The model's job (structured output, one call)

**Input:** change appetite; follow-up answers; for each category: slug, name, essential flag, which options exist and their **relative size** (e.g. "trim = 10% less than usual"); whether keeping everything fits the room, and by how much each option closes the gap, expressed as **ranks**, not amounts. No money figures are needed for the choice.

**Output schema:**
```json
{
  "intro": "<≤ 200 chars, no digits>",
  "budgets": [
    { "category_slug": "dining-out", "option": "trim", "reason": "<≤ 80 chars, no digits>" }
  ],
  "goal_order": ["<draft goal key>"]
}
```

**Goal order:** the user's order from the `goal_priority` follow-up wins; the model's `goal_order` is used only when the user didn't answer it.

**Rules Rails enforces:**
- Every candidate category appears **exactly once**; `option` must be one that exists for it.
- `reason` required for `trim`/`stretch`, optional for `keep`.
- **No digits anywhere in model text.** Every figure on screen comes from Rails, so a made-up number can't appear. (Same principle as the coach's figure check, enforced more strictly.)
- Appetite: "Keep things as they are" → all `keep` (the model isn't called for budgets; only the intro); "Small trims" → at most 3 trims, no stretch.
- Text is checked for length and treated as plain text in the app (no markup).

**On failure:** one retry with the validation errors; then a **deterministic fallback**: keep everything, except for "Small trims", trim the 2 largest non-essential categories; generic reasons from a fixed list. The draft records `source: "fallback"`, and the screen looks the same.

**Model and cost:** `claude-haiku-5-5`, one call of roughly 1–2k tokens; checked against the daily AI cap; per-user limit of 5 drafts a day.

### 6.4 Draft storage (amended 2026-11-28, D-032)

`POST /api/v1/plan_proposals` builds candidates, calls the model, validates, and stores a `plan_proposals` row whose payload contains **every Rails figure** (usual, chosen amount per category, bills, goals with G2 results, income check), the model's text, `source` (`model` / `fallback`), model id and timestamps. `GET /api/v1/plan_proposals/current` returns it. Limit: 5 drafts a day per user (`AiRateLimit`, daily window).

**Statuses:** `draft` → `approved`, or `superseded` when a newer draft replaces it (at most one open draft per user). **Stale** isn't stored: it's worked out on read (older than 7 days, or created before a newer import), and a stale draft must be redrafted.

### 6.5 What the draft screen shows (C6, canvas step 4)

- Intro line: model text, with the app adding "built from your last **N** months" from Rails.
- **Everyday budgets:** per category: name; "Your usual: $X" (+ the model's reason when trimmed); chosen amount; **Adjust** opens the −/+ sheet (as in the Plan tab), changing the draft only. "Show N more categories".
- **Bills:** from step 3.
- **Goals:** G2 figures, as on the canvas (weekly amount and first milestone; debt payoff time, interest, and the what-if).
- **Fit line:** "Fits your usual income" or "This plan is **$X** a month over your usual income. You can adjust below." (Rails figures).
- Footer: "Nothing is saved until you approve. Estimates assume a fixed APR and no new charges."
- Buttons: **Adjust** (scrolls to budgets) and **Approve plan**.

## 7. Plan approval (PL2) (amended 2026-11-28, D-032)

`POST /api/v1/plan_proposals/:id/approve`, in **one DB transaction**:
- `category_budgets` for each chosen amount, `effective_from` = 1st of the current month (user's time zone). This **replaces this month's budget only for categories in the draft**; budgets in other categories stay untouched.
- `obligations` from the chosen bills and `goals` (with any starting balances) from the draft. A bill or goal **with the same name as an existing one is skipped**, and the response lists what was kept (e.g. "You already had Rent; kept yours") so the app can say so.
- The proposal → `approved`, `approved_at` set; links from created rows back to it (as in the schema).

Rules:
- **A second approve** returns **409** with `{"error": "already_approved", "approved_at": "…"}`. The app treats this as success and goes to Home, so a double tap or a retry after a timeout never shows an error when the plan saved.
- A **stale** draft (§6.4) is refused with 422 and the screen offers "Refresh my plan".
- Another user's proposal is a 404.
- After approval the app goes to **Home**, which now shows Left to spend.

Adjustments before approval: `PATCH /api/v1/plan_proposals/:id` with item changes (budget amount, bill on/off or edited, goal fields); Rails recomputes the fit line and G2 figures and returns the updated draft.

**Build as three PRs:** PL1 (drafting, server #24) → PL2 (approval, server #25) → C6 (approval screen, client #20).

## 8. Step 3: a few uncertain merchants

Reuses C2b's review groups: the **top 3–5 groups** by count, the same chips and pick behaviour (with `also_updated`). "Looks good" continues; "Skip for now" also continues; the footer says "N more are waiting in Activity whenever you're ready." This step comes **before** the draft so the usual spending is computed on better data.

## 9. Acceptance criteria

**Automated:**
1. `Onboarding::Facts`: pay pattern for weekly / biweekly / twice-monthly / monthly / irregular fixtures; side income threshold; likely-bill rule (±10%, ±3 days, 2 of 3 months).
2. `PlanCandidates`: medians over full months only; rounding; option eligibility (essential categories never `stretch`; < 2 months → keep only); hand-calculated examples.
3. Income check: fits / doesn't fit, with irregular floor and side income on/off.
4. Model output validation: missing category, unknown option, digits in text, too long, extra keys → retry → fallback; "keep everything" appetite makes no budgets call.
5. Follow-ups: unknown/ineligible slot rejected; AI failure skips silently.
6. Approval: one transaction (failure midway leaves nothing saved), idempotent, stale draft refused, ownership 404.
7. No merchant names, descriptions or account names in any model request (request-capture test).

**On the phone (fresh demo user, after import):**
1. From Home's "Make a plan", the whole flow completes in **under 5 minutes** (time it once for the demo).
2. Question 1 is pre-filled correctly for the demo payroll; question 2 shows the Venmo side income; question 3 lists rent, phone and card payment.
3. The draft's "Your usual" figures match Plan → Budgets for the same months after approval.
4. Airplane mode during drafting gives a friendly error with Retry; with the AI cap reached, the fallback draft appears and works.
5. After approval, Home shows Left to spend, the Plan tab shows the plan, and the Coach can answer "Am I on track this week?".

## 10. Owner decisions (all Approved, 2026-11-25)

1. **Follow-ups from a fixed menu of slots** (Claude picks and phrases; Rails owns options), rather than free-form questions. Recommended: much safer and testable; conversational onboarding is v1 anyway.
2. **No digits in any model text** for the plan, with all figures from Rails. Recommended: stricter than a figure check and simpler to enforce.
3. **Trim sizes:** trim = 10% below usual, stretch = 20%, essentials never stretched, at most 3 trims for "Small trims". Recommended as a gentle default (D-002 "small changes first").
4. **Likely-bill detection in onboarding** (simple rule in §4.1) to pre-fill question 3, while full recurring-bill detection stays v1. Recommended: saves typing and makes the demo feel smart, deterministic and testable.

## 11. Later (v1)

Conversational onboarding; re-planning from the Plan tab ("Make a new plan"); plan eval with an LLM judge for reason quality; weekly targets for undated goals; full recurring-bill detection.
