# Budget Buddy — MVP Scope (two milestones and v1)

**Status:** APPROVED by product owner (2026-11-22). Updated 2026-11-22 with approved changes D-016, D-018 and D-019.
**Phase:** 3, MVP definition
**Builds on:** `claude/PRODUCT_BRIEF.md` (approved), `claude/DESIGN_DECISIONS.md`

---

## 1. MVP goal

A brand-new user can import their money history, get a coach-drafted plan (category budgets, obligations, goals), approve it, and see **what's left to spend this week**, **what's due**, and **how their goals are progressing**. All on synthetic demo data, with a secure, user-scoped API.

## 2. Timeline (D-018)

The original 3-day target was estimated at 56–82 h of work vs ~24–30 h available, so the MVP is delivered in two milestones within the ~2-week window:

- **M1 (Days 1–3): secure multi-account foundation with AI categorization.** P1–P4 in full (including the Claude categorization fallback), minimal client (new tab layout, accounts, import, review, transfers), synthetic demo data, minimal CI, categorization eval. If M1 runs over, transfer matching moves to the start of M2.
- **M2 (Days 4–7): plan, goals and coach.** Obligations, goals, Left to spend / Today, monthly dashboard built first as non-AI features; then coach onboarding, plan drafting and Q&A on top; Q&A eval.
- **v1 (remaining days):** §7.

## 3. Success criteria

1. A new user goes from **sign-up to an approved plan in under 5 minutes** on demo data (end of M2).
2. **Every figure the coach states matches** the corresponding app view.
3. **Zero cross-user data access** in automated tests.
4. **Re-importing the same file creates zero duplicates.**

## 4. MVP features, in priority order

Never cut P1–P3. Fallback order in §6.

| P   | Feature                       | MVP behaviour                                                                                                                                                                                                           | Milestone                 |
| --- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| 1   | **Security foundation**       | Every endpoint needs a valid Kinde token; each user sees only their own data; AI tools bound to the current user; rate limits and daily AI token cap                                                                    | M1                        |
| 2   | **Accounts and CSV import**   | Add an account (name, kind, purpose); upload a CSV in **one generic format**; normalize, validate, skip duplicates; "data through <date>" per account                                                                   | M1                        |
| 3   | **Transfer matching (basic)** | Suggest matches (same amount, opposite sign, ≤ 3 days, different accounts of the same user); user confirms or rejects; confirmed transfers excluded from spending and income                                            | M1 (may slip to early M2) |
| 4   | **Categorization**            | Flat category list (+ Insurance, Other; one Income); merchant memory → keyword rules → **Claude Haiku** for the rest; low confidence → review; corrections teach merchant memory                                        | M1                        |
| 5   | **Coach onboarding**          | Structured tap-to-answer questions (income pattern, account purposes, fixed bills, goals, change appetite), may reference imported data; light conversation (≤ 2 follow-ups); review of the top 3–5 uncertain merchants | M2                        |
| 6   | **Coach-drafted plan**        | Rails computes candidate category budgets, obligations and goal figures; the coach chooses and explains; stored as a proposal; nothing saved until approved (atomic approval)                                           | M2                        |
| 7   | **Goals: all three types**    | Upcoming payment, purchase (incl. emergency fund without a date), debt payoff. See §5                                                                                                                                   | M2                        |
| 8   | **Home: Today / This week**   | **Left to spend this week**; obligations due in the next 7 days (with "mark paid"); goal contributions due this week; data-through date                                                                                 | M2                        |
| 9   | **Monthly dashboard**         | Budget vs actual per category for the month; one tap from Home                                                                                                                                                          | M2                        |
| 10  | **Coach Q&A**                 | Free-form questions answered through read-only, user-scoped tools (spending summary, budget vs actual, goal status)                                                                                                     | M2                        |

**Engineering showcase in MVP (D-016):** minimal GitHub Actions CI (M1); eval-lite: categorization accuracy (M1), Q&A tool-and-figure correctness (M2).

**Navigation (D-019):** tabs **Home, Plan, Activity, Coach**. First run: sign in → accounts and import → onboarding → top uncertain merchants → plan approval → Home.

## 5. Key definitions

**Left to spend this week (D-018; full spec in Phase 5):** this week's share of the user's flexible category budgets minus flexible spending so far this week. Needs no account balance (CSV can't provide one reliably). Obligations and goal contributions due this week are shown as separate lists, not subtracted. Obligations are marked paid manually in the MVP.

**Obligation vs upcoming-payment goal (PO-4):** an obligation is paid from regular cash flow and shown as "due"; an upcoming-payment goal is saved toward ahead of time.

**Goals:**

- Progress: user-recorded "set aside" contributions, or a linked confirmed transfer into a savings account; debt progress from balance updates.
- Upcoming payment / purchase: remaining amount, weeks left, needed per week, on-track or behind.
- Debt payoff: this month's interest, payoff date and total interest at the current payment, savings from +$X/month (fixed APR, monthly compounding, no new charges; estimates).
- Milestones: computed 25/50/75/100% with projected dates.

## 6. Cuts and fallback order

| Earlier idea                               | MVP                                              | v1                                |
| ------------------------------------------ | ------------------------------------------------ | --------------------------------- |
| Automatic recurring-bill detection         | Obligations captured in onboarding, editable     | Auto-detect and suggest           |
| Venmo + bank CSV formats                   | One generic format (demo data for every account) | Real formats                      |
| Rich monthly dashboard                     | Simple budget-vs-actual list                     | Charts, trends                    |
| "What's this savings for?" prompt          | Manual transfer-to-goal link                     | Automatic prompt                  |
| Balance-based "safe to spend"              | Budget-based "left to spend"                     | Opening balances / balance column |
| Automatic "paid" detection for obligations | Manual "mark paid"                               | Match by amount/date              |

**Fallback if behind:** within M1, CT0 → transfers screen (confirm via API/demo) → AI3. Within M2: coach follow-ups → milestones → transfer-to-goal linking → monthly dashboard. Beyond that (owner approval needed): Q&A → Claude step in plan drafting (keep deterministic draft) → Claude categorization.

## 7. v1

- Conversational onboarding; visible, editable financial profile
- Proactive insights on Home
- Recurring-bill detection; "what's this savings for?" prompt; automatic obligation-paid matching
- Interest-charge detection in imports
- Day-by-day spending trend forecast (bounded by C-1); balance-based safe to spend
- Re-import nudges; optional cash entry; real Venmo and bank CSV formats
- Docker Compose; AWS deployment pipeline (ECR, least-privilege IAM, GitHub OIDC); Expo web demo on S3 + CloudFront; encrypted DB backups to S3 — all on a **very low AWS budget**
- Full LLM evaluation (scheduled, cost-capped, LLM-as-judge for tone)
- Logo and visual redesign (cuter, design-oriented squirrel), polish, README, demo

## 8. Non-goals

Live bank connections; moving money or paying bills; investment or tax advice; shared budgets; multiple named budgets; the AI performing calculations or saving anything without approval; real personal financial data (fresh synthetic-only dev database, PO-11); storing uploaded CSV files.

## 9. Dependencies and risks

- Plan rev. 4.1 (handoff #02) sequences the work; KA step 4 (owner) unblocks S1b.
- "Left to spend this week" needs the Phase 5 spec before W1.
- AI reliability in a live demo: structured onboarding, Rails-validated proposals and approval cards limit the risk.
