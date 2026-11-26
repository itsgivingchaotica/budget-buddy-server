# Budget Buddy — MVP Implementation Plan

Status: **Revision 4.1 — Approved (2026-11-24).** First approved on 2026-11-22 (D-018, handoff #02). Updated on 2026-11-24 for handoff #04 (D-019 to D-021 and `docs/product/SPEC_LEFT_TO_SPEND.md`) and for PO-27/PO-28 (UP1). **M1 is in progress** (started 2026-11-24): DB0 and S1b are done, but not committed. S1a is done and approved (PO-20). KA is done (step 4 on 2026-11-24).
Updated: 2026-11-24 (handoff #04). **Changes:**
- **W1 unblocked:** it now follows the approved spec. The endpoint is renamed `GET /outlook/week`, and its acceptance tests are the spec's §10 worked examples.
- **`obligation_payments` schema confirmed:** the minimal schema from the spec (§2.2).
- **Home screen (C3):** labels, conservative rounding and the four states, from the spec.
- **Brand:** the Forest Floor palette and the Bricolage Grotesque / Inter fonts apply to new screens (D-020).
- **Categories:** default flexible/fixed labels from spec §7. The new category is named **"Debt Payments"**; the legacy tag "Debt Repayment" is untouched (resolves PO-26).
- **UP1:** the Expo SDK upgrade is placed before C0 (PO-27/PO-28).
Revised: 2026-11-22 (4.1). **Changes in 4.1:** AI-0, a minimal S4 and AI2 move into M1 (TR1 slips first if M1 runs over); home metric renamed **"Left to spend this week"** (budget-based) with manual "mark paid" via `obligation_payments`; tabs Home / Plan / Activity / Coach; first-run order; minimal GitHub Actions CI and eval-lite (D-016); fresh synthetic-only dev database (DB0, PO-11); Insurance and Other added to the categories, one Income category (PO-8); uploaded CSVs parsed and discarded (Q-27). PO answers are recorded in `PROGRESS.md`.
Revised: 2026-11-22 (4). Revision 4 re-sequences the plan around the approved product direction (`docs/product/PRODUCT_BRIEF.md`, `docs/product/DESIGN_DECISIONS.md`, Approved entries) and the draft MVP scope (`docs/product/MVP_SCOPE.md`, P1–P10). The feasibility review behind it is in [`PROGRESS.md`](PROGRESS.md), section "Feasibility review for plan revision 4"; open product-owner questions are referenced here as **PO-n**.
Revision 3 (superseded): archived byte-for-byte in `project-knowledge/2026-11-22/tree/docs/IMPLEMENTATION_PLAN.md`.

**Goal:** a secure, user-scoped MVP where a new user imports CSV history from several accounts, gets a coach-drafted plan (category budgets, obligations, goals), approves it, and sees what's left to spend this week, what's due, and how goals are progressing. All on synthetic data.

**Naming note.** Product decisions are written **D-0nn** (three digits, e.g. D-006). Revision 3's data tasks were **D-1…D-4**; to avoid confusion, revision 4 keeps those IDs only where the task survives and uses **DM-n** for new data-model tasks.

**Ground rules (unchanged from revision 3, plus one)**
- **Additive and reversible schema changes only.** Nothing is dropped, renamed or renumbered. Every migration has a working `down`. Any data rewrite is preceded by a backup and a before/after check, and needs explicit approval.
- **Legacy data is frozen, not deleted.** `budgets`, `entries`, `tags`, `entries_tags` stay in the database untouched (including TD1's orphaned rows). Removing them is a separate, later decision (PO-10).
- **Small, testable steps**, each logged in `docs/PROGRESS.md`. **No commits or pushes without approval.** Credentials are never printed, committed or sent to the client.
- **The AI proposes; the app calculates; the user decides** (D-002). No figure shown to the user is produced by the model.

---

## 1. What changed since revision 3

| Area | Revision 3 | Revision 4 | Why |
|---|---|---|---|
| Ownership root | `user → budgets → entries/transactions` | `user → accounts → imports/transactions`; plan objects (`category_budgets`, `obligations`, `goals`, `merchant_rules`, `financial_profiles`) belong directly to the user | D-006 (the app is the budget), D-007 (accounts) |
| Budgets | Kept; new-budget flow fixed (C-B) | **Retired as a concept** (soft): no new table references `budgets`; legacy table and endpoints are frozen | D-006, MVP non-goal "multiple named budgets" |
| Categories | 5 categories + 38 tags; slugs on categories; tag uniqueness fixes | **One flat category list** (spending categories from today's Expense tags, plus Income and Transfers) with optional labels; tags frozen as legacy | D-012 |
| Plan lines | `entries` (free-text recurrence) as "planned" amounts | `category_budgets` (per category per month) and `obligations` (structured recurrence) | D-002, D-006 |
| Goals | — | `goals` (3 types) + `goal_contributions` | D-011, D-013 |
| Transactions | Budget-owned, `account_label` text | Account-owned; duplicate key per account | D-007 |
| CSV formats | Two formats (signed / debit-credit) | **One generic format** (§2.4) | MVP_SCOPE §5, Q-19 |
| Transfers | Not modelled | `transfer_links`: suggested → confirmed | D-007 |
| Assistant | Spending Q&A only | Onboarding questions, plan drafting, Q&A (three read-only tools) | D-002, D-004 |
| Home screen | Budget tab | Today / This week, monthly dashboard one tap away | D-003 |
| Timeline | 3 days, everything | Two milestones: **M1 Days 1–3, M2 Days 4–7**, borrowed from the v1 fortnight; see §3 | D-018 (PO-2, PO-3) |
| Home metric | — | **"Left to spend this week"**: budget-based, no balances; obligations and goal contributions listed, not subtracted | D-018 (PO-5, PO-6) |
| Engineering showcase | — | Minimal GitHub Actions CI (M1); eval-lite: categorization (M1), Q&A (M2) | D-016 |

---

## 2. Architecture decisions

Decisions AD1, AD5 (duplicate detection), AD6 (model choice), AD7 (categorization pipeline) and §2.3 of revision 3 (model capabilities) **still apply**, with the adjustments noted. AD2, AD3, AD4, AD8 and AD9 are revised.

| # | Decision | Choice and reasoning |
|---|---|---|
| AD1 | **API authentication** (unchanged) | Kinde access token as `Authorization: Bearer`, checked by `Kinde::TokenVerifier` (S1a): RS256, `iss`, `exp`, and **`aud` required** once controllers authenticate (S1b). `sub` → `users.kinde_id`. SR-1 governs linking existing users. |
| AD2 | **Ownership** (revised) | Every query starts at `current_user`. Direct children: `accounts`, `category_budgets`, `obligations`, `goals`, `merchant_rules`, `financial_profile`, `plan_proposals`, `ai_usage`. Account children (`imports`, `transactions`) are reached with `has_many :through` (`current_user.transactions`), **not** a denormalized `user_id`, so ownership can't drift. Any ID in a request body (`account_id`, `category_id`, `transaction_id`, `goal_id`) is resolved through the caller's scope or the global category list; failure → 404 (owned records) or 422 (reference data). Another user's record → **404**. |
| AD3 | **Transactions** (revised) | `transactions` belong to an `account`; amount is `decimal(12,2)`, **money in +, money out −**, from the account holder's view. Duplicate key per account (§2.3). |
| AD4 | **Categories** (revised) | The existing `categories` table is reused. New rows hold the flat list; the 5 current rows stay, marked `kind = legacy`, IDs 6–10 untouched so the legacy client keeps working until its screens are hidden. Stable references use `slug`. |
| AD5 | **Duplicate detection** (adjusted) | Revision 3 §2.2 algorithm, with `account_id` replacing `budget_id` and `account_label` in the key. If the CSV has a `transaction_id` column, it is the key instead (§2.4). |
| AD6 | **AI model** (unchanged) | `claude-haiku-5-5` for every AI feature, model IDs from env: `ANTHROPIC_CATEGORIZATION_MODEL`, `ANTHROPIC_ASSISTANT_MODEL` (covers onboarding follow-ups, plan drafting and Q&A). AI-0 confirms account access before AI code. |
| AD7 | **Categorization** (adjusted) | Merchant memory → keyword rules → Claude, in batches; Claude chooses from a server-built **category** allowlist (slugs of active spending categories + Income; never Transfers, which only transfer confirmation assigns). Confidence < 0.6 → `needs_review`. |
| AD8 | **Coach** (revised) | One Rails service family, three uses, all stateless calls with only the caller's data (D-008): **(a) onboarding follow-ups** — given structured answers, return ≤ 2 follow-up questions as structured output; **(b) plan drafting** — given Rails-computed facts (category averages, captured obligations, stated goals), return a proposal that only *chooses and explains* amounts from candidate values Rails supplied; Rails recomputes and validates every figure before showing it; **(c) Q&A** — tool loop (≤ 4 rounds) with read-only tools bound to `current_user`: `get_spending_summary`, `get_budget_vs_actual`, `get_goal_status`. Tool inputs contain only dates/periods and goal IDs that are re-resolved through `current_user.goals`. |
| AD9 | **Calculations** (revised) | Plain Ruby services, `BigDecimal` throughout, no caching: `SpendingAnalytics` (summary, budget vs actual, category averages; Transfers excluded), `RecurrenceSchedule` (structured obligation recurrence → due dates in a window), `GoalCalculator` (per-week needed, on-track, milestones), `DebtCalculator` (monthly interest, payoff date, total interest, savings from +$X; fixed APR, monthly compounding, no new charges), `LeftToSpend` (**"Left to spend this week"** = this week's share of the user's flexible category budgets − flexible spending so far this week; no account balance; obligations and goal contributions due this week are returned as separate lists, **not subtracted**; exact proration, states and edge cases defined by the approved spec **`docs/product/SPEC_LEFT_TO_SPEND.md`**, D-021). Coach tools are thin wrappers around these services, so coach figures always match the views (success criterion 2). |
| AD10 | **Plan approval** (new) | A coach draft is stored server-side as a `plan_proposals` row (`status: proposed`), never as live plan objects. `POST /plan_proposals/:id/approve` validates and creates `category_budgets`, `obligations` and `goals` **in one database transaction**. Edits before approval patch the proposal. This enforces "nothing saved without approval" and gives an audit trail. *(Not in the approved concept list: PO-14.)* |
| AD11 | **Budgets retired (soft)** (new) | See §2.1. |
| AD12 | **CI and evaluation** (new, D-016) | **CI:** one minimal GitHub Actions workflow per repo, on push and pull request. Server: Ruby 3.3.0 + a Postgres service container, `bin/rails db:test:prepare && bin/rails test`. Client: `npm ci`, a `tsc` check that fails if the error count rises above the committed baseline (TS0), and `npm run test:ci` once CT0 works. CI needs **no secrets**: tests use fake key fetchers and a fake Anthropic client, and WebMock blocks real HTTP. **Eval-lite:** offline scripts, never run on every push because they call the paid API. Categorization eval (M1): a labelled golden synthetic set from the DEMO-G generator, run through the real pipeline, reporting accuracy overall, per category and per source (memory/rule/ai), the `needs_review` rate, and tokens/cost. Q&A eval (M2): fixed questions over demo data, checking the expected tool was called and every figure in the answer equals the `SpendingAnalytics` output. Run locally or via `workflow_dispatch`. Reports are written to `docs/evals/`. |
| AD13 | **Uploaded files** (new, Q-27) | CSVs are parsed in memory and discarded; the file is never stored. `imports` keeps counts, the filename and `row_errors` as **line number + error code only** (no raw row text), so no financial text is retained outside `transactions` or written to logs (D-008). |

### 2.1 Budgets: retire, or keep one implicit budget per user? (D-006)

| | **Soft retire (recommended)** | One implicit budget per user |
|---|---|---|
| Schema | New tables reference `user`/`account`. `budgets`, `entries`, `tags`, `entries_tags` untouched. | Every new table gets `budget_id`; unique index on `budgets.user_id` (dev has 1 budget, so it applies cleanly); auto-create on `/me`. |
| Matches approved design | Yes: transactions owned through accounts (D-007), no budget concept (D-006). | Contradicts D-006/D-007: transactions owned by a budget, and the multi-budget CRUD endpoints still exist and must be locked down. |
| Client | Legacy store keeps its `currentBudget` code until legacy screens are hidden (LG1). New store slices never mention budgets. Header title changes. **C-B is dropped.** | Legacy screens keep working unchanged, but every new screen must carry `currentBudget.id` and new routes nest under `/budgets/:id`. |
| Controllers / S3 | Legacy endpoints scoped (S3-L) or made read-only (PO-10). New controllers scoped from `current_user`. | S3 as written in revision 3; new controllers must also check budget ownership. |
| Tests | Existing 20 scaffold tests keep passing; ownership matrix covers legacy + new endpoints. | Same, plus tests that "exactly one budget" holds. |
| Later cost | Dropping legacy tables later is one approved migration with nothing depending on them. | Removing `budget_id` from every new table later is a multi-table migration. |

**Recommendation: soft retire.** It removes C-B, D-3's tag rewrite and D-4 entirely, and it is the only option consistent with the approved decisions.

### 2.2 Data model (all new tables additive; columns indicative)

| Concept | Table | New or reuse | Key columns | Notes / tradeoffs |
|---|---|---|---|---|
| Account | `accounts` | **New** | `user_id`, `name`, `kind` (checking/savings/credit_card/p2p/cash/other), `purpose` (spending/bills/savings/side_income/other), `purpose_note`, `opening_balance` + `opening_balance_on` (nullable, PO-6), `archived_at` | Unique `(user_id, lower(name))`. "Data through" = `max(transactions.posted_on)`, computed, not stored. No reuse candidate exists. |
| Import | `imports` | **New** (revision 3 T1, re-parented) | `account_id`, `filename`, `status`, `row_count`, `inserted_count`, `duplicate_count`, `error_count`, `row_errors` jsonb (line number + error code only, AD13), `data_from`, `data_through` | `user` reached through `account`. The uploaded file is never stored (Q-27). |
| Transaction | `transactions` | **New** (revision 3 T1, re-parented) | `account_id`, `import_id` (null for manual/cash), `posted_on`, `amount` decimal(12,2), `description`, `normalized_description`, `external_id`, `base_key`, `occurrence`, `category_id`, `categorization_source` (user/memory/rule/ai/transfer/none), `confidence`, `needs_review` | Unique `(account_id, base_key, occurrence)`; partial unique `(account_id, external_id) WHERE external_id IS NOT NULL`; indexes `(account_id, posted_on)`, `(category_id)`. `entries` are **not** reused: they are planned lines, budget-owned, with free-text recurrence; and all 44 dev entries are Income plans, not bank movements. |
| Transfer link | `transfer_links` | **New** | `outflow_transaction_id` (unique), `inflow_transaction_id` (unique), `status` (suggested/confirmed/rejected), `day_gap`, `confirmed_at` | A link table, not a column on `transactions`: it carries suggestion state, remembers rejections (so they aren't re-suggested) and enforces one link per transaction. On **confirm**, both transactions get category `transfers` (source `transfer`), so analytics has a single exclusion rule ("category ≠ Transfers"). Unconfirming restores the previous category. Both sides must be in `current_user.transactions` and in **different** accounts. |
| Category | `categories` | **Reuse** + columns | add `slug` (unique), `kind` (spending/income/transfer/legacy), `position`, `active`, default labels `need_want`, `fixed_variable`, `recurrence_label` (nullable enums) | See §2.5 for the mapping. Old rows: `kind = legacy`, `active = false`. **How, without rewriting rows:** the migration adds `kind` with default `legacy` and `active` with default `false`, so Postgres gives the existing rows those values as the columns are created (no `UPDATE` statement). It then drops the defaults, so new rows must state their kind. The `down` migration removes the columns. `category_type` is left as is (legacy `categories#default` still returns the old 5). |
| Category labels | (columns above) | Reuse | — | MVP: labels are **global defaults per category**, read-only in the UI. Per-user overrides or per-transaction labels: v1 (PO-7). |
| Category budget | `category_budgets` | **New** | `user_id`, `category_id`, `period` (`month` only in MVP), `amount`, `effective_from` (first of a month), `source` (coach/user), `plan_proposal_id` | Unique `(user_id, category_id, effective_from)`. A row applies from its month until a later row replaces it, so no per-month copies. Spending categories only. |
| Obligation | `obligations` | **New** | `user_id`, `name`, `amount`, `category_id`, `account_id` (nullable: pays from), `first_due_on`, `recurrence` (none/weekly/biweekly/monthly/yearly), `interval` (int ≥ 1), `ends_on`, `source` (interview/user/coach), `plan_proposal_id`, `archived_at` | Structured recurrence, so no free-text parsing. Debt minimum payments are obligations. Paid status lives in `obligation_payments` (next row). |
| Obligation payment | `obligation_payments` | **New** (4.1, D-018, D-021, spec §8.1) | `obligation_id` (FK, `on_delete: :restrict`; obligations are archived, never deleted), `due_on` (date, not null), `paid_on` (date, not null; defaults to today in the user's time zone, may be set earlier, never in the future), timestamps | **Schema confirmed (2026-11-24): the spec's proposal, as is.** I dropped revision 4.1's `marked_by` and `transaction_id`: both only matter for v1's automatic matching, and adding them then is an additive migration. Unique `(obligation_id, due_on)`. A row exists = that occurrence is paid; "mark unpaid" deletes the row (the user's own toggle; no legacy data involved). `due_on` must be a date `RecurrenceSchedule` actually produces for that obligation (else 422). Owned through `obligation → user`. The alternative, a `last_paid_on` column on `obligations`, can't represent paying one occurrence but not an earlier one, or undoing a single toggle. |
| Goal | `goals` | **New** | `user_id`, `goal_type` (upcoming_payment/purchase/debt_payoff), `name`, `target_amount`, `target_date` (required for upcoming_payment; optional for purchase, e.g. an emergency fund, PO-4), `starting_balance`, `current_balance`, `apr`, `monthly_payment`, `status` (active/completed/archived), `plan_proposal_id` | One table with type-specific nullable columns + per-type validations. Milestones are **computed** (25/50/75/100% with projected dates), not stored. |
| Goal contribution | `goal_contributions` | **New** | `goal_id`, `kind` (set_aside/linked_transfer/balance_update), `amount`, `balance_after` (debt), `contributed_on`, `transaction_id` (nullable, must be the caller's, on a confirmed transfer) | Debt progress = `balance_update` rows; `goals.current_balance` mirrors the latest one. Unique `transaction_id` where present. |
| Merchant rule | `merchant_rules` | **New** (revision 3 AI1, retargeted) | `user_id`, `merchant_key`, `category_id`, `hits`, `last_used_at` | Unique `(user_id, merchant_key)`. Points at categories, not tags. |
| Financial profile | `financial_profiles` | **New** | `user_id` (unique), `answers` jsonb + `answers_version`, typed fields the calculations read: `pay_frequency`, `next_pay_on`, `typical_pay_amount`, `change_appetite` (small/medium/large), `week_starts_on` (0–6, Ruby `wday`, not null, **default 1 = Monday**), `time_zone` (IANA name validated against `ActiveSupport::TimeZone`/TZInfo; null until set), `onboarding_completed_at`; `coach_notes` jsonb (v1) | jsonb keeps the question set flexible; anything Rails calculates from is a typed, validated column. **Time zone (PO-12, spec §2):** the client sends the device's IANA zone with `GET /me` (S2/C0) and onboarding (ON1). It's stored only if the profile has none yet; onboarding can change it. W1 needs it; until it's set, W1 uses `UTC` and adds an assumption saying so. |
| Plan proposal | `plan_proposals` | **New** (AD10, PO-14) | `user_id`, `status` (proposed/approved/rejected/superseded), `payload` jsonb, `explanations` jsonb, `model`, `approved_at` | Approval creates plan rows in one transaction. |
| AI usage | `ai_usage` | **New** (revision 3 S4) | `user_id`, `day`, `feature` (categorize/onboarding/plan/assistant), `requests`, `input_tokens`, `output_tokens` | Unique `(user_id, day, feature)`. The daily cap reads it before any Claude call. |
| Users | `users` | **Reuse** + columns | add `kinde_id` (unique, nullable), unique index on `lower(email)` | Revision 3 S2 + the surviving half of D-3 (D-1 found 0 duplicate emails). |
| Budgets, entries, tags, entries_tags | (existing) | **Frozen legacy** | — | Not read by any new code. TD1–TD3 stay as accepted debt. |

**Category budgets and goals: one "targets" table, or separate? Separate tables (recommended).** A shared table would need many nullable columns (APR, balance and monthly payment are meaningless for a category budget; period and category are meaningless for a goal), and the two have different lifecycles: a budget resets every month and never completes, while a goal accumulates toward completion. Every analytics query would also need a type filter. What they genuinely share, the approval flow (`source`, `plan_proposal_id`) and the coach-proposal plumbing, is shared in code: a small `PlanItem` concern and `plan_proposals`.

### 2.3 Duplicate detection

Revision 3 §2.2 still applies (occurrence numbering inside a file; `INSERT … ON CONFLICT DO NOTHING`), with these changes:
- `base_key = SHA-256(posted_on | amount_cents | normalized_description)`, unique **per account**: `(account_id, base_key, occurrence)`.
- If the file has a `transaction_id` column, rows with a value are keyed on `(account_id, external_id)` instead.
- Known limitations (pending → posted description changes, uneven counts in overlapping files) remain accepted.

### 2.4 Generic CSV format (MVP; proposal, PO-18)

- **One file = one account**, chosen at upload. There's no account column, so a file can't scatter rows across accounts.
- **Encoding and syntax:** UTF-8 (BOM allowed), comma-delimited, RFC 4180 quoting, header row required.
- **Columns** (header names case-insensitive, surrounding whitespace ignored, any order, unknown extra columns ignored and reported):

| Column | Required | Rules |
|---|---|---|
| `date` | yes | `YYYY-MM-DD` (preferred) or month-first `M/D/YYYY` (one- or two-digit month and day, so `MM/DD/YYYY` too; **PO-18 change, 2026-11-24**). Two-digit years and day-first dates are rejected. Anything else is a row error. No times or time zones. The posted date, not the authorization date. |
| `description` | yes | Non-empty, ≤ 255 characters after trimming. Normalized for keys and rules: upper case, whitespace collapsed, trailing store numbers / card fragments stripped by a fixed rule list. |
| `amount` | yes | Signed, **negative = money out of this account, positive = money in**. Optional leading `$` and thousands separators; `(12.34)` = −12.34; at most 2 decimals; zero → skipped with a warning. USD only. For a credit-card account, purchases are negative and payments to the card positive. |
| `transaction_id` | no | Bank/app transaction ID; when present, it becomes the duplicate key. |
| `balance` | no | Running balance after the row. Stored on the import (latest balance + date) only if Phase 5 uses balances (PO-6). |

- **Limits:** 2 MB and 10,000 rows per file (about 3–5 years of a typical checking account), processed within the request. Bulk insert keeps 10,000 rows under ~5 s locally (to be verified in I2).
- **Pending transactions** must not be in the file (documented in the template).
- Downloadable template and example in `bb-server/public/csv-templates/generic.csv`. Format notes for users, with a change log: `generic-notes.txt` beside it.
- **Change to PO-18 (2026-11-24, product owner):** accept `M/D/YYYY` as well as `MM/DD/YYYY`, because many bank exports drop leading zeros. Still rejected: two-digit years (`2/3/26`) and day-first dates (`13/1/2026`). A day-first date with both parts ≤ 12 (e.g. `3/2/2026` meant as 3 February) can't be detected and is read month first; the notes say so.

### 2.5 Category migration (D-012; additive)

| Today | Becomes |
|---|---|
| **Expense** tags (15): Groceries, Utilities, Rent, Dining Out, Entertainment, Transportation, Healthcare, Education, Clothing, Personal Care, Gifts, Travel, Subscriptions, Home Improvement, Debt Repayment | **17 spending categories** (PO-8): the 15 names, plus Insurance and Other. **One new name:** the approved spec (§7) and PO-9 call the debt category **"Debt Payments"** (slug `debt-payments`). These are **new rows**, so the legacy *tag* "Debt Repayment" isn't renamed or touched. This resolves PO-26 with no data rewrite. **Default `fixed_variable` labels (spec §7):** variable = Groceries, Dining Out, Entertainment, Transportation, Healthcare, Clothing, Personal Care, Gifts, Travel, Home Improvement, Other; fixed = Rent, Utilities, Subscriptions, Insurance, Debt Payments, Education. Card payments from checking go to it unless both sides are imported and confirmed as a transfer (PO-9). **Other** is a valid choice for users, rules and the AI; uncertain rows still go to `needs_review` rather than Other. Default labels seeded per category (e.g. Rent = need, fixed, recurring; Insurance = need, fixed, recurring; Other = no labels). |
| **Income** tags (4): Salary, Freelance, Gifts Received, Bonuses | **One Income category** (PO-8). |
| — | **Transfers** category (`kind = transfer`), assigned only by transfer confirmation. |
| **Savings & Goals** tags (8) | **Not categories.** Saving is a transfer. The names become onboarding goal suggestions (e.g. Home Down Payment → purchase; Debt Reduction → debt payoff; **Emergency Fund → purchase-style goal without a target date**, PO-4). Retirement Savings isn't offered as an MVP goal. |
| **Miscellaneous** tags: Essential / Non-Essential, One-time / Recurring, Planned / Unexpected | Labels: Essential → need, Non-Essential → want; One-time / Recurring → `recurrence_label`; Planned / Unexpected → dropped (no label in D-012). |
| **Budgeting Strategy** tags: Fixed Expense / Variable Expense, Needs / Wants, Discretionary | Labels: fixed / variable; need / want; Discretionary → want. |
| The 5 category rows (IDs 6–10 in the old database; **1–5 in the new MVP database**, DB0) | Kept, `kind = legacy`, `active = false` (via column defaults, §2.2), slugs `legacy-expense` etc. (slugs are set by the idempotent seed, keyed on name; only the new `slug` column is written). |
| 38 tags, 76 `entries_tags` rows (33 orphaned), 44 entries | **Untouched.** No row is moved, rewritten or deleted. New code doesn't read them, so TD1's orphans never matter. The legacy endpoints keep working as before. |

Why this path is safest: it only inserts rows and adds columns. There's no `UPDATE` of existing tags or entries, so no backup-and-approval step is needed. Revision 3's D-3 rewrite of the default tags' `user_id` (1 → NULL) **is no longer required**, and neither is D-4. The new categories are inserted by an idempotent, slug-keyed seed (`db:seed` twice adds nothing) that's safe on the existing dev database. It skips the legacy tag loop once the slug columns exist, which resolves K8.

---

## 3. Feasibility and sequencing

The full MVP (P1–P10) was estimated at **56–82 focused hours**, against roughly 24–30 in three days. The product owner therefore approved **two milestones** (D-018):

- **M1: secure multi-account foundation with AI categorization (Days 1–3; estimate 31–46 h, see below).**
  - P1, P2 and P4 in full, including the Claude fallback (AI-0, minimal S4, AI2). P3 too, unless M1 runs over.
  - A fresh synthetic-only dev database, the new tab layout, the Activity screens and synthetic demo data.
  - Minimal CI and the categorization eval.
  - **If M1 runs over, TR1 (transfer matching) moves to the start of M2**, not AI2.
- **M2: plan, goals and coach (Days 4–7; estimate 31–48 h, plus 3–4 h if TR1 moves in).** Moving the AI work out (−4 to −6 h) is offset by mark paid, the Plan tab, the onboarding context and review queue, and the Q&A eval. M2 is also tight for 4 days.
  - First, as manual (non-AI) features: obligations (with mark paid), category budgets, goals, Left to spend / Home and the monthly dashboard.
  - Then on top of those tables: coach onboarding (first-run order, D-019), plan drafting, Q&A and the Q&A eval.

**Updated M1 estimate (4.1):**

| Block | Tasks | Hours |
|---|---|---|
| Security | S1b ✅, S2 ✅, S3/S3-L ✅, TS0, C0 | 5–7.5 (S1b done, about 1.5 h of it) |
| Fresh dev database | DB0 ✅ | 0.5 (done) |
| **Expo SDK upgrade** | **UP1** (PO-27/PO-28; flagged to the PO at 12 h) | **8–16** |
| Navigation | LG1 (4 tabs, Activity stack) | 1–1.5 |
| Data + import | DM-1, DM-2, T1, I1, I2, C2 | 7–10 |
| Transfers | TR1 + transfers screen | 3–4 |
| Categorization (no AI) | AI1, AI3, review screen + Activity badge | 3.5–5 |
| **AI (moved into M1)** | AI-0, S4-min, AI2 | **4–6** |
| Demo data | DEMO-G (+ golden labels for the eval) | 2–3 |
| **CI** | CI1 (server and client workflows) | **1–2** |
| **Categorization eval** | EV1 | **1.5–2.5** |
| Client tests | CT0 | 1–1.5 |
| End-of-M1 check | M1 QA / buffer | 1.5–2 |
| **Total** | | **39–62 h** (was 31–46 h before UP1); **about 37–60 h remaining** after DB0 and S1b |

**With UP1 (2026-11-24), M1 is roughly 1.5–2 times the ~24–30 h in Days 1–3.** It's realistically Days 1–5 (PO-28). The original analysis, before UP1, follows. **M1 doesn't fit Days 1–3 as specified.** Even with the agreed slips (TR1 moves to M2, then CT0), it's **27–40 h** against roughly 24–30 h, so it fits only at the optimistic end. **PO-21** asks the product owner to choose: accept that M1 may take part of Day 4, or approve a further slip order (§7).

The order inside M2 is deliberate. The coach only *drafts* rows for tables that already work and are tested. If time runs out, the app still calculates and shows everything from manually entered data. If the coach is late, nothing else breaks.

---

## 4. M1 — Days 1–3

Order:
- **Current order (PO, 2026-11-24):** … AI-0 → S4-min → **AI2 → UP1 (one-day cap, incl. phone rebuild) → LG1 → C2 → phone test with demo data → TR1 → C2b**, then EV1 and the rest.
- **Backend:** DB0 → KA (step 4) → S1b → S2 → S3 → DM-1 → DM-2 → T1 → I1 → I2 → AI1 → AI3 → DEMO-G → AI-0 → S4-min → AI2 → EV1 → TR1. TR1 is last so that it's the piece that moves to M2 if M1 runs over. It can start earlier if things are on schedule.
- **Brand (D-020), for every new or rebuilt screen (LG1, C2, C2b, and M2's C3–C8):** the **Forest Floor** palette as theme tokens in one file (`constants/Theme.ts`, replacing the template `Colors.ts` for new screens): Pine #2F5D46 (primary), Moss #7A9A5B, Fern #DCE6D2, Birch #F6F1E7 (background), Acorn #B5652E (mascot only), Chestnut #8E4A1F (accent text), Bark #3A2A1E (text), Ember #C0563A (over budget, always with an icon + label). Fonts: **Bricolage Grotesque** (headings) and **Inter** (body), replacing SUSE on new screens, via `@expo-google-fonts/*` (new dependencies, installed in UP1/LG1 with approval). Legacy screens keep their styling until removed. The mascot is used only in onboarding, the coach avatar, empty states and celebrations. Logo work waits for v1.
- **Client:** TS0 → C0 (moved before DM-2, PO-33) → UP1 (one-day cap) → LG1 → C2 (Activity: accounts, import, transactions) → C2b (Activity: review + badge, transfers)
- **Separate tracks:** CT0 and CI1. They never block backend work. CI1's server job goes in as soon as S1b lands.

| ID | Task (revision 3 link) | Depends on | Acceptance criteria |
|---|---|---|---|
| **S1a** | Token verifier. **Done and approved** (`3b54035`, `feature/auth`, local only, PO-20). Work continues on `feature/auth` until the M1 review. | — | 50 focused / 70 full tests pass (re-confirmed 2026-11-22). |
| **DB0** *(new, PO-11)* | ✅ **Done 2026-11-24 (uncommitted).** **Fresh synthetic-only development database.** `config/database.yml` development `database:` reads `ENV.fetch("BB_DEV_DATABASE", "bb_server_mvp_development")`. dotenv-rails loads `.env` before `database.yml` is evaluated, so the switch can live in `.env`. Create it with `bin/rails db:create db:schema:load db:seed`. **The old `bb_server_development` database and its backup (`backups/bb_server_development_2026-11-22.dump`) are kept, not dropped.** Switching: unset `BB_DEV_DATABASE` (new MVP database, the default) / `BB_DEV_DATABASE=bb_server_development bin/rails …` (old database). Recorded in `PROGRESS.md` and `CLAUDE.md`. **M1/M2 migrations are applied only to the new database.** The old one stays at schema `20250419232612`, as a reference and rollback copy for the pre-MVP code. With the new code it raises a "pending migrations" error, so inspect it with `psql` in a read-only session instead. Migrating it needs separate approval. | — | `bin/rails runner 'puts ActiveRecord::Base.connection.current_database'` prints the new name by default and the old name with the override. The old database's row counts are unchanged (users 2, budgets 1, tags 38, entries 44, entries_tags 76). The test database is unaffected. |
| **KA** | Kinde API audience. **Done (step 4 confirmed 2026-11-24 on a physical iPhone; claims recorded in PROGRESS and matching `bb-server/.env`).** Temporary claims log removed (PO-29); committed on `bb-client` `feature/ios-dev-build` @ `6a61d74`. | — | `iss` and `aud` confirmed and recorded in PROGRESS without the token. ✅ |
| **S1b** | ✅ **Done 2026-11-24 (uncommitted; see PROGRESS).** Unchanged from revision 3: `Authenticatable`, `before_action :authenticate!` on every `api/v1` controller, `aud` required, memoized verifier, 401/503 JSON, reason-only logging. | S1a, KA | As revision 3. |
| **S2** | ✅ **Done 2026-11-24 (uncommitted; see PROGRESS).** Unchanged from revision 3 (`users.kinde_id`, `GET /me`, SR-1), plus: `/me` creates an empty `financial_profile` and returns `onboarding_completed`. Adds the unique `lower(email)` index (from revision 3 D-3). | S1b | As revision 3, plus profile created exactly once. |
| **S3** *(rescoped)* | ✅ **Done 2026-11-24 (uncommitted; see PROGRESS).** One scoping pattern from `current_user` (AD2) for every new controller; a shared `OwnershipMatrix` request-test table. **S3-L, legacy endpoints:** budgets via `current_user.budgets`, entries via the caller's budgets, tags = global defaults plus the caller's own; `user_id`/`default_tag`/`category_type` removed from params; category writes → 403 (as revision 3). *Alternative if PO-10 chooses: legacy write endpoints → 410.* CORS allowlist from `CORS_ORIGINS`; `authorization` filtered from logs. | S2 | Cross-user → 404 on every existing endpoint. Injected `user_id` ignored. The matrix is extended by each new resource task. |
| **TS0** | ✅ **Done 2026-11-24 (uncommitted; see PROGRESS).** Unchanged from revision 3 (tsc baseline, grouped by cause). | — | Baseline file + counts. |
| **UP1** *(new, PO-27; **target SDK 54** (PO, 2026-11-25; 55+ needs a newer Xcode, see §11); **capped at one working day**, 2026-11-24: if unfinished, stop, report blockers, continue on SDK 51 with the development build, and finish in v1)* | **Expo SDK 51 → current SDK**, on its own branch, one SDK step at a time (`npx expo install expo@^N --fix`, `expo-doctor`, a `tsc` check and a run on the phone after each step). Known work: the New Architecture, now required; React 19; Expo Router 3 → current; **NativeWind 2 → 4** (new Tailwind, Babel and Metro setup plus `global.css`, and every `className` screen re-checked); Reanimated 3 → 4; Storybook 7 → current or removed; replacing unmaintained native packages (`react-native-modal-datetime-picker`, `react-native-pie-chart`); removing unused `react-native-config`/`react-native-dotenv`. **Kinde:** evaluate replacing `@kinde-oss/react-native-sdk-0-7x`, whose native dependencies are unmaintained, with Kinde's current Expo SDK, keeping the `audience` parameter. Re-run the KA claims check after any auth change. Restore `expo-dev-client` once a compatible version is in place. Estimate 8–16 h, time-boxed at 12 h (PO-28). | TS0 | `expo-doctor` is clean. The app builds with the installed Xcode and runs on the phone, in Expo Go if the store version matches, or as a development build. Login returns the same `iss`/`aud`. The legacy screens still render. No new tsc errors against the TS0 baseline. |
| **C0** | ✅ **Code done 2026-11-24; phone test pending (uncommitted).** Moved before DM-2 (PO-33). Unchanged from revision 3 (axios instance with token, 401 → login, `GET /me`). | S2, KA, TS0 | Login → home works. No new tsc errors. |
| **CT0** | Unchanged from revision 3 (Jest for Expo 51, ≤ 1.5 h box). | — | `npm run test:ci` runs. |
| **LG1** *(new; replaces C-B; tabs per D-019)* | Freeze the legacy UI. New tab layout: **Home** (Today / This week placeholder until W1/C3), **Plan** (placeholder until M2), **Activity** (a stack: accounts, import, transactions, review, transfers), **Coach** (placeholder). The Budget/Categories tabs and the `category/` modal stack are removed from navigation, but the files are kept. The header no longer shows `currentBudget.name`. No legacy store code is deleted. | C0 | App boots to the four tabs; legacy screens unreachable; no new tsc errors. |
| **DM-1** *(new; replaces D-2/D-3/D-4)* | ✅ **Done 2026-11-24 (uncommitted; see PROGRESS).** Categories: add `slug` (unique, partial where not null), `kind`, `position`, `active`, and the label columns `need_want`, `fixed_variable`, `recurrence_label`. Legacy rows get `kind = legacy`, `active = false` via column defaults (§2.2), and their slug from the seed (new column only). An idempotent slug-keyed seed adds the flat list (§2.5): 17 spending categories with the spec §7 `fixed_variable` labels, plus Income and Transfers. `GET /categories` returns active categories in `position` order with labels; legacy `categories#default` is unchanged. Migrations run on the **MVP database only** (DB0). | S1b (S3 for the ownership matrix row) | `db:seed` twice adds nothing; `db:reset` gives the expected 19 active rows + 5 legacy rows; every spending category has the spec §7 label; legacy endpoints unchanged (existing tests pass); the `down` migration restores the previous schema. |
| **DM-2** *(new)* | ✅ **Done 2026-11-24 (uncommitted; see PROGRESS).** `accounts` table + `GET/POST/PATCH /accounts`, `DELETE` = archive (sets `archived_at`; transactions kept). Name + purpose required. | S3 | Ownership matrix rows; unique name per user (case-insensitive); archive hides the account but keeps its data. |
| **T1** *(revised)* | `imports` + `transactions` per §2.2, owned through accounts. | DM-1, DM-2 | Model tests: uniqueness per account, sign convention, `external_id` partial index; reachable only via `current_user.transactions`. |
| **I1** *(revised: one format)* | `CsvImport::Parser` for the §2.4 generic format. | T1 | Unit tests: BOM, quoted comma, both date forms, bad date, bad amount, parentheses, `$1,234.56`, zero amount, missing required header (whole file rejected naming the required headers), extra columns, `transaction_id` present/absent, empty file. Bad rows reported by line number without stopping others. |
| **I2** *(revised)* | `POST /accounts/:account_id/imports` (multipart; the file is parsed in memory and discarded, row errors stored as line + code only, AD13), §2.3 duplicate detection, summary with `data_from`/`data_through`. `GET /transactions` (filters `account_id`, `from`, `to`, `category`, `needs_review`; paginated), `PATCH /transactions/:id` (category only), `DELETE /transactions/:id`. `GET /accounts` includes `data_through` per account. | I1 | Same file again → `inserted 0`; rearranged rows → `inserted 0`; overlapping files; same row in two different accounts → both kept; other user's account → 404; too large / wrong type → 422; 10,000 rows < 5 s locally. |
| **TR1** *(new, P3; first to move to M2 if M1 runs over)* | `TransferMatcher`: after each import, suggest pairs among the caller's unconfirmed transactions: same absolute amount, opposite sign, **different accounts**, `|day gap| ≤ 3`; one-to-one, closest date first, ties left unsuggested; previously rejected pairs never re-suggested. `GET /transfer_links?status=suggested`, `POST /transfer_links/:id/confirm`, `POST /transfer_links/:id/reject`, `POST /transfer_links` (manual pair), `DELETE /transfer_links/:id` (unconfirm, restoring categories). | I2 | Tests: exact match; 4-day gap → no suggestion; same account → none; two candidates → closest; tie → none; rejected pair not re-suggested; confirm sets both to Transfers; unconfirm restores; cross-user transaction IDs → 404. **Delete rule (PO, 2026-11-24):** `DELETE /transactions/:id` on a transaction in any `transfer_links` row returns **422** and deletes nothing; test it when TR1 lands. |
| **AI1** *(revised)* | `Categorization::Pipeline` → `MerchantMemory` → `KeywordRules` (~40 patterns → category slugs), Claude step stubbed until AI2. Runs after import on uncategorized rows; leftover rows → `needs_review` until AI2 exists. | T1, DM-1 | Rows matched by memory/rules never reach the (fake) AI client. |
| **AI3** | Unchanged in intent: `PATCH /transactions/:id` with a new category upserts a `merchant_rules` row; source `user`. | AI1, I2 | Next import of that merchant → source `memory`, no AI call. |
| **AI-0** *(moved into M1)* | Unchanged from revision 3: `anthropic ~> 2.12`, `AnthropicClient` wrapper (key from `ANTHROPIC_API_KEY`, model IDs from env, retry/timeout settings confirmed from the SDK source), and one real structured-output smoke call (`script/anthropic_smoke.rb`, not part of the suite). | S3 | Smoke call OK; the wrapper can be swapped for a fake; the key never appears in logs. |
| **S4-min** *(moved into M1; rest of S4 in M2)* | `rack-attack`: a general per-IP limit plus a per-user limit on `POST /transactions/categorize` (e.g. 20/hour). `ai_usage` table; `AiBudget.check!(user, :categorize)` runs **before any Claude call** against `AI_DAILY_TOKEN_CAP`, and usage is recorded from the response's `usage`. | AI-0 | Over the limit → 429 JSON; over the cap → 429 and the fake client gets **no call**; usage rows add up correctly. |
| **AI2** *(moved into M1)* | Claude categorizer as in M2 below / revision 3: category-slug allowlist (AD7; never Transfers), batches ≤ 50, structured output `{results: [{index, category_slug, confidence}]}`, effort `low`, only the merchant key (cleaned description), amount and account purpose sent, **never the date** (data minimization, D-008; PO, 2026-11-24), descriptions treated as data. Refusal or `max_tokens` → `needs_review`. `POST /transactions/categorize` processes ≤ 100 rows per call → `{processed, remaining}`. The import response tells the client whether rows remain. ~~**PO rule (2026-11-24):** rows the keyword rules deliberately skip (transfer-like, P2P payments such as Zelle/Venmo, Amazon) go to Claude first and reach review only if confidence < 0.6.~~ **Superseded (PO, 2026-11-25):** transfer-like rows (`TRANSFER TO/FROM`, `CASH OUT`/`CASHOUT`, or naming another of the user's own accounts) **never reach Claude**: a deterministic pre-check (`Categorization::TransferCheck`, after merchant memory) sends them straight to `needs_review` with source `none`, for TR1. The prompt's low-confidence instruction for own-account transfers stays as a backup. P2P payments (Zelle/Venmo) and Amazon still go to Claude first and reach review only if confidence < 0.6. Each item sent includes the account's `purpose`, so money into a `side_income` account can be suggested as Income. Items carry only `index`, `merchant`, `amount`, `account_purpose` (AI1 already sends these). | AI1, S4-min | Revision 3 AI2 tests, with categories instead of tags: allowlist only; an invented slug is discarded; refusal → `needs_review`; an API 429 loses no data and the next call resumes; the injection description can only reach an allowed category or `needs_review`. One manual run against the real API on demo data, logged in PROGRESS. |
| **EV1** *(new, D-016)* | **Categorization eval-lite.** The DEMO-G generator also writes a labelled golden set (about 300 synthetic transactions with expected category slugs, including ambiguous and noisy descriptions). `bin/rails eval:categorization` runs it through the real pipeline (memory empty, so rules → Claude) and writes `docs/evals/categorization-<date>.md`: accuracy overall, per category and per source; the `needs_review` rate; the confusion pairs; **a separate critical-error count: rows labelled `transfers` that were filed as a spending or income category** (PO, 2026-11-25); tokens and estimated cost. It's run manually or via `workflow_dispatch`, **never on push**. | AI2, DEMO-G | The report is generated and the first baseline is recorded in PROGRESS. It runs within the daily AI cap. The golden set contains no real data. |
| **CI1** *(new, D-016)* | `bb-server/.github/workflows/ci.yml`: on push/PR, Ruby 3.3.0 + `postgres:14` service, `bin/rails db:test:prepare && bin/rails test`. `bb-client/.github/workflows/ci.yml`: `npm ci`; `scripts/tsc-baseline-check` (fails if the `tsc --noEmit` error count exceeds the committed TS0 count); `npm run test:ci` once CT0 works (until then the job is skipped with a note). An `eval.yml` with `workflow_dispatch` only, for EV1/EV2. | S1b (server job), TS0 (client job) | Both workflows pass on GitHub. **They only run once pushed, which needs your approval each time.** No secrets are needed for CI. `eval.yml` needs an `ANTHROPIC_API_KEY` repository secret, which **you** add (PO-22). Until then the evals run locally. |
| **C2** *(revised; Activity tab)* | Under **Activity**: an accounts list with purpose and "data through", add/edit (name, kind, purpose); an import screen (`expo-document-picker`, choose account, upload, summary, error states); and a transactions list (filters: account, category, needs review). After an import, it calls `categorize` until `remaining = 0`. | C0, I2, AI2 | On the simulator: add 3 accounts, import 3 demo files, re-import one → 0 inserted; categorization completes. |
| **C2b** *(new; Activity tab)* | Review screen (`needs_review` first, category picker that teaches memory) and a **"needs review" count badge on the Activity tab** (D-019). Transfers screen: suggested pairs with confirm/reject. The transfers screen moves with TR1 if TR1 slips. | C2, AI3 (TR1 for transfers) | Re-categorize one row → the next import of that merchant uses memory; the badge count matches `GET /transactions?needs_review=true`; confirm a suggested transfer → it disappears from spending. |
| **DEMO-G** *(new; was part of DEMO)* | Deterministic synthetic data generator (PROGRESS, feasibility §4.3): writes generic-format CSVs for Checking, Savings and "Venmo", including an overlapping second export and one malformed file. `rake demo:seed` imports them **through the real import pipeline** for a demo user. | I2, TR1 | Same seed → byte-identical files; demo import produces the expected transfer suggestions; the generator contains no real personal data. |

**M1 tests (required):** S1b auth matrix; SR-1; ownership matrix for every legacy and new endpoint; category seed idempotency; parser and duplicate cases above; transfer matching cases; pipeline order (memory/rules before AI); AI2 allowlist, refusal and injection cases; rate limit and daily cap checked before any Claude call. No network in tests (WebMock). CI1 runs the server suite on every push (once pushes are approved).

---

## 5. M2 — Days 4–7

Order: (TR1 + transfers screen, if moved from M1) → S4 (rest) → OB1 → DM-3 → AN1 → G1 → G2 → W1 → AN2 → ON1 → ON2 → PL1 → PL2 → AS1 → AS2 → EV2 → client (C3 → C7 → C8 → C5 → C6 → C4) → CT → Q1 → DEMO

AI-0, S4-min and AI2 have moved to M1 (4.1).

| ID | Task (revision 3 link) | Depends on | Acceptance criteria |
|---|---|---|---|
| **S4** *(rest)* | Per-user rack-attack limits on onboarding follow-ups, plan drafting and the assistant (e.g. 30 messages/hour). The `ai_usage` daily cap extended to all four AI features. | S4-min | Over limit → 429; over cap → 429 **before** any Claude call, for each feature. |
| **OB1** *(new, P6 prerequisite; + mark paid in 4.1)* | `obligations` CRUD + `RecurrenceSchedule` (due dates in a window for none/weekly/biweekly/monthly/yearly × interval, respecting `ends_on`; month-end clamping, e.g. Jan 31 → Feb 28/29). **Mark paid (D-018):** `obligation_payments` (§2.2); `POST /obligations/:id/payments` `{due_on}` (idempotent) and `DELETE /obligations/:id/payments/:due_on`. `GET /obligations/due?from=&to=` returns each occurrence with `paid: true/false`. All lookups go through `current_user.obligations` (spec §8.1; schema confirmed in §2.2: `obligation_id`, `due_on`, `paid_on`). | S3 | Hand-calculated due-date tests incl. month-end and leap years; marking a date that isn't a real occurrence → 422; marking twice → one row; unmark restores "due"; `paid_on` in the future → 422; another user's obligation → 404 for both POST and DELETE. |
| **DM-3** *(new)* | `category_budgets` table + `GET /category_budgets?month=`, `PUT /category_budgets` (bulk upsert for one `effective_from`). | DM-1 | Effective-from semantics tested (a March row applies to April until replaced). |
| **AN1** *(revised)* | `SpendingAnalytics`: `summary(user, from:, to:, account_ids: nil)`, `budget_vs_actual(user, month:)` (category budgets vs actual spending; Transfers excluded; income shown separately), `category_averages(user, months:)` (for plan drafting: trailing-N-month mean and median per category, with the months actually covered by data). `RecurrenceExpander` over entries is **dropped**. | T1, OB1, DM-3 | Fixture tests with hand-calculated values; Transfers excluded; empty range → zeros; months with no data aren't counted as zero spending. |
| **G1** *(new, P7)* | `goals` + `goal_contributions` + CRUD; per-type validations; linking a contribution to a transaction requires a confirmed transfer **into** a savings-purpose account owned by the caller (the "link" part can be cut: MVP_SCOPE §5). | S3, TR1 | Validation and ownership tests; a linked transaction can't be linked twice. **Delete rule (PO, 2026-11-24):** `DELETE /transactions/:id` on a transaction linked from a `goal_contributions` row returns **422** and deletes nothing; test it when G1 lands. |
| **G2** *(new, P7)* | `GoalCalculator` (remaining, weeks left, needed per week, on-track/behind, milestones 25/50/75/100% with projected dates; a purchase goal **without a target date**, e.g. an emergency fund (PO-4), shows progress and milestones only, with no per-week need or on-track status) and `DebtCalculator` (D-011). Assumptions returned with each result for the UI. | G1 | Hand-calculated tests: debt payoff with known amortization (e.g. $5,000 at 22% APR, $200/month → payoff month and total interest checked against a reference schedule); payment ≤ monthly interest → "never pays off" flag, not an infinite loop; +$X savings; goal past its date. |
| **W1** *(new, P8; **unblocked 2026-11-24**, D-021)* | **Implements `docs/product/SPEC_LEFT_TO_SPEND.md`** (approved), which is the source of truth for formulas, states and the response. `WeeklyOutlook` service + **`GET /api/v1/outlook/week`** (no parameters; scoped to `current_user`; renamed from `/home/week` to match the spec):<br>• **left to spend** (§3): per-day share of each flexible category's monthly budget across the user's calendar week, taken from the right month when the week crosses a month boundary; minus flexible spending (refunds net, floored at 0; uncategorized rows count; Transfers, Income, fixed categories, archived accounts and future-dated rows excluded) up to `min(today, data_through)`; `BigDecimal`, no display rounding on the server;<br>• **state** with precedence `no_plan` > `stale` (> 7 days) > `no_data_this_week` > `ok` (§4.1);<br>• **bills due** (§8.1): rolling **next 7 days** (today … today + 6) **plus unpaid occurrences earlier this week** (`overdue: true`), each with `paid`; never subtracted;<br>• **goal contributions this week** (§8.2): active, dated upcoming-payment/purchase goals only;<br>• `data_through` (earliest of the per-account latest `posted_on`, §2), `uncategorized_count`, and the §6 assumptions.<br>"Flexible" = active spending category with `fixed_variable = variable` (spec §7, seeded by DM-1). Week and "today" use `financial_profiles.week_starts_on` / `time_zone` (PO-12). | AN1, OB1, G2, DM-3 | **The spec's §10 worked examples 1–9 as service tests with the hand-calculated values** (e.g. example 2: 1 × 640/30 + 6 × 700/31 = **156.82**). A **request test for the §9 response shape** (money as strings). An **ownership test**: another user's budgets, transactions, obligations and goals never affect the result. Obligations and goal contributions never change `left`. |
| **AN2** *(revised)* | `GET /analytics/summary`, `GET /analytics/budget_vs_actual?month=` (no budget in the path). | AN1 | Shape, validation (≤ 366 days), ownership. |
| **ON1** *(new, P5)* | Onboarding question set (versioned constant): income pattern (typed: `pay_frequency`, `typical_pay_amount`, `next_pay_on`, PO-5), account purposes, fixed bills (captured as draft obligations), goals (type, name, amount/date, or balance/APR/payment), change appetite, week start and time zone (defaults Monday + device time zone, PO-12). **Questions may reference imported data** (D-019). `GET /onboarding/context` returns Rails-computed facts: likely paydays (recurring income amounts and dates), large recurring charges, months of data per account. It's used to prefill choices; the user confirms everything. `GET/PUT /profile`. Also `GET /onboarding/review_queue`: the **top 3–5 uncertain merchants**, grouped by normalized merchant and ranked by transaction count × total amount among `needs_review` rows. | S2, DM-2, I2, AI2 | Typed fields validated; answers round-trip; the context endpoint only uses the caller's transactions; the review queue never returns more than 5 merchants; another user's profile is unreachable. |
| **ON2** *(new, P5; first to cut)* | Light conversation: `POST /onboarding/follow_ups`: given the structured answers, Claude returns ≤ 2 follow-up questions (structured output); answers stored in `answers`. | ON1, S4 | Fake-client tests: never more than 2; refusal/error → onboarding continues without follow-ups. |
| **PL1** *(new, P6)* | `PlanDrafter`: Rails builds candidates (category averages → suggested budget = recent median adjusted by `change_appetite`, rounded; obligations from answers; goals from answers with GoalCalculator figures). Claude chooses among candidates and writes short explanations (structured output). Rails validates (categories active, amounts within candidate bounds, totals recomputed) and stores a `plan_proposals` row. `POST /plan_proposals`, `PATCH /plan_proposals/:id`. | AN1, OB1, G2, ON1, AI-0 | Tests: a proposal amount outside the candidate bounds is clamped or rejected; an unknown category is dropped; refusal → a deterministic, non-AI draft with the same structure. |
| **PL2** *(new, P6)* | `POST /plan_proposals/:id/approve`: one DB transaction creates category budgets, obligations and goals, then marks the proposal approved; a second approve → 409. | PL1, DM-3, G1 | Atomicity test (failure mid-way creates nothing); other user's proposal → 404. |
| **AS1** *(revised, P10)* | `POST /assistant/messages` (no budget in the path). Tools: `get_spending_summary(from, to)`, `get_budget_vs_actual(month)`, `get_goal_status(goal_id?)`, built per request with `current_user`. ≤ 4 tool rounds; refusals handled. | AN2, G2, S4 | Revision 3 AI tool-access tests, with `goal_id` re-resolved through `current_user.goals` (another user's goal ID → tool error, no data). |
| **AS2** | Unchanged from revision 3 (history limits, trimmed tool output, no content in logs). | AS1 | As revision 3. |
| **EV2** *(new, D-016)* | **Q&A eval-lite.** About 15 fixed questions over the demo user's data (e.g. "How much did I spend on groceries last month?", "Am I over budget on dining this month?", "How far along is my car fund?"), each with the expected tool. `bin/rails eval:assistant` checks that (a) the expected tool was called and (b) every money figure in the answer equals the corresponding `SpendingAnalytics` / `GoalCalculator` output (parsed and compared to the cent). It writes `docs/evals/assistant-<date>.md`. Run manually or via `workflow_dispatch`, never on push. | AS1, DEMO-G | Report generated; first baseline recorded in PROGRESS; any mismatch is treated as a bug (success criterion 2). |
| **C3** *(revised; Home tab; spec §5)* | **Home:** the W1 outlook. Section labels **"Left to spend · <user's week days, e.g. Mon–Sun>"** and **"Bills · next 7 days"**. **Conservative rounding in one shared client helper** (`utils/money.ts`): `left ≥ 0` → whole dollars **rounded down** ("$63 left"); `left < 0` → "$0 left · over by $22" with the overage **rounded up**, in Ember **with** a warning icon and text label; allowance ("of $149 for the week") rounded down; a progress bar of spent / allowance. **Four states, precedence `no_plan` > `stale` > `no_data_this_week` > `ok`** (the API returns one), each with its spec §4.1 message and action. "Includes N transactions to review" when `uncategorized_count > 0`. A detail sheet shows per-category allowance/spent/left, the assumptions and the data-through date. Bills have a mark-paid toggle; overdue items say "Was due <date>, mark paid if done". Goal contributions due this week are listed. The monthly dashboard (budget-vs-actual) is one tap away. | W1, AN2, OB1 | Figures match the API. Unit tests for the rounding helper (63.73 → "$63"; −21.67 → "over by $22"; 149.33 → "$149"; exact whole dollars unchanged). Each state renders its message. Mark paid toggles the bill without changing the headline number. |
| **C7** *(new; Plan tab)* | Goals list/detail under **Plan**: progress, per-week need, milestones, debt interest view; "set aside" and balance-update actions. | G2 | Debt "+$X/month" figure matches the API. |
| **C8** *(new; Plan tab, D-019)* | **Plan** tab: category budgets for the month (view/edit), bills (obligations: list, add, edit, archive) and goals (C7). This is the manual (non-AI) path into the same tables the coach drafts. | DM-3, OB1, C7 | A user can set a budget, add a bill and add a goal without the coach; Home reflects them. |
| **C5** *(new; first run, D-019)* | First-run flow, in this order: **sign in → add accounts and import (Activity screens from C2, in a guided wrapper) → onboarding questions (prefilled from `onboarding/context`; optional follow-ups via ON2) → review only the top 3–5 uncertain merchants (`onboarding/review_queue`) → plan draft (C6) → Home.** Any remaining review items show as the Activity badge (C2b). It resumes where the user left off if the app is closed. | C2, ON1, ON2, PL1 | Sign-up → approved plan in < 5 min on demo data (success criterion 1), timed and recorded in PROGRESS. |
| **C6** *(new)* | Plan card: category budgets, obligations, goals with explanations; edit amounts; approve. | PL2 | Approve → Home and Plan show the approved plan. |
| **C4** *(revised)* | Coach chat (Q&A) with starter questions and "used: tool" notes. | AS1 | Coach figures match the dashboard and goal views (success criterion 2). |
| **CT** | As revision 3, covering the new store slices. | CT0 | `npm run test:ci` passes; tsc ≤ baseline. |
| **Q1** | As revision 3: full suites + manual end-to-end with a **new** Kinde account on a fresh database. | all | Recorded in PROGRESS. |
| **DEMO** *(revised)* | README (architecture diagram: client ↔ Rails ↔ Claude, where authorization happens), AI design notes, demo script, `CLAUDE.md` updated. Demo data from DEMO-G. | Q1 | A newcomer can reach the demo flow from the README. |

**M2 tests (required):** RecurrenceSchedule, obligation payments, GoalCalculator, DebtCalculator and LeftToSpend against hand-calculated values; analytics with Transfers excluded; plan validation and atomic approval; AI tool access (no owner IDs in schemas, user-bound tools, 404 before any Claude call, turn limit, tool output = service output); ownership matrix rows for every new resource.

---

## 6. Revision 3 → revision 4 task map

| Revision 3 | Revision 4 | Note |
|---|---|---|
| P1–P4 | Done | Day 0 complete |
| S1a | S1a | Done (`3b54035`) |
| KA | KA | Done (2026-11-24) |
| S1b, S2 | S1b, S2 | Unchanged (S2 also creates the profile and adds the email index) |
| S3 | S3 + S3-L | Ownership root moves to user/accounts; legacy endpoints scoped or made read-only |
| S4 | S4-min (M1) + S4 rest (M2) | Categorize limit + daily cap in M1; other AI features in M2 |
| TS0, C0, CT0, CT, Q1 | Same | Unchanged |
| C-B | **Superseded** | No budgets (D-006); replaced by LG1 |
| D-1 | Done | Re-run 2026-11-22: counts unchanged |
| D-2 | DM-1 | Slugs, now on the flat list |
| D-3 | **Mostly superseded** | Tag uniqueness and the default-tag `user_id` rewrite are no longer needed (tags frozen). The email unique index moves to S2 |
| D-4 | **Superseded** | Entries are frozen legacy |
| T1, I1, I2 | T1, I1, I2 | Re-parented to accounts; one CSV format |
| AI-0, AI1, AI2, AI3 | Same IDs, **all in M1** (4.1) | Categories instead of tags |
| AN1, AN2 | AN1, AN2 | Transactions vs category budgets; entry recurrence parser dropped |
| AS1, AS2 | AS1, AS2 | Not budget-scoped; adds `get_goal_status` |
| C1 | **Superseded** | Legacy screens hidden (LG1); slug-based categories come with C2b/C6 |
| C2 | C2 + C2b | Accounts, import, review, transfers |
| C3 | C3 | Home: Left to spend / This week + monthly dashboard |
| C4 | C4 | Coach Q&A |
| DEMO | DEMO-G + DEMO | Multi-account synthetic generator in M1 |
| — | DM-2, DM-3, TR1, OB1, G1, G2, W1, ON1, ON2, PL1, PL2, LG1, C2b, C5, C6, C7 | New in revision 4 |
| — | DB0, CI1, EV1, EV2, C8, `obligation_payments` (in OB1) | New in revision 4.1 |

---

## 7. If time runs out

- **M1 slips to M2 (D-018, then MVP_SCOPE §6):** **TR1 + the transfers screen first** (not AI2) → CT0 and the client CI job's test step → AI3. TR1 is still P3 and is never cut, only moved. **Proposed further slip order, pending PO-21:** EV1 report polish (keep a raw accuracy number) → M1 QA buffer.
- **Never cut in M1:** DB0, S1b–S3, C0, DM-1, DM-2, T1/I1/I2 with duplicate detection, AI-0/S4-min/AI2, the CI1 server job.
- **Within M2 (MVP_SCOPE §6 order):** ON2 follow-ups → milestones (G2) → linked-transfer contributions (G1) → monthly dashboard (C3 second view; Home stays).
- **Beyond that (owner approval needed):** Q&A (AS1/C4/EV2) → PL1's Claude step (keep the deterministic draft) → Claude categorization.
- **Never cut:** the four required test areas (auth, ownership, calculations, AI tool access), W1's `data_through`, PL2 atomic approval, manual mark paid.

## 8. Risks

| Risk | Mitigation |
|---|---|
| M1 is estimated at 31–46 h vs ~24–30 h in Days 1–3, even with the AI and CI additions approved | Slip order (§7); PO-21; the order puts TR1 last so it can move cleanly |
| ~~"Left to spend" not yet specified~~ | Resolved 2026-11-24: `SPEC_LEFT_TO_SPEND.md` approved (D-021); W1 unblocked |
| A wrong "today" or week, from a missing or bad time zone | Device time zone sent with `/me` and onboarding; validated IANA names; `UTC` fallback stated as an assumption; W1 tests pin the clock and the zone |
| "Flexible" depends on category labels, which are global and read-only in the MVP (PO-7) | Seed labels carefully (DM-1); the spec decides which labels count as flexible |
| CI runs only after a push, and pushes need approval each time | Run the same commands locally before asking; CI1 is ready when the first push is approved |
| Eval cost and secrets | Evals never run on push; they stay within `AI_DAILY_TOKEN_CAP`; the GitHub secret is added by you (PO-22) |
| Transfer false positives (same amount, coincidental) | Suggestions require user confirmation; rejections remembered |
| Coach plan figures diverge from views | AD8/PL1: Rails computes candidates and re-validates; tools wrap the same services |
| Credit cards (sign, payments look like transfers) | PO-17 |
| ~~Kinde KA step 4 not done → S1b blocked~~ | Resolved 2026-11-24 |
| UP1 runs long (NativeWind 4 and Kinde SDK changes are the main unknowns) | Time-box at 12 h (PO-28); backend work proceeds in parallel; fall back to SDK 51 for M1 client work |
| SDK 51 development build on Xcode 16.4 (above the supported 16.2) and iOS 26 | Works today without `expo-dev-client`. Free-account builds expire after 7 days. The Mac's IP is baked into debug builds, so rebuild if it changes. All of this goes away after UP1 |
| Legacy client code rots while hidden | LG1 keeps it unreachable but compiling; removal is a later approved task |
| AI risks (availability, beta tool runner, refusals, accuracy) | As revision 3 §9 |

## 9. New dependencies and configuration

- **Server gems:** `jwt` (added in S1a), `rack-attack`, `anthropic (~> 2.12)`; `webmock` (test). `csv` comes with Ruby 3.3.
- **Client:** `expo-document-picker` (via `npx expo install`). Added 2026-11-23 for the iOS development build: `react-native-svg` (missing peer), plus SDK 51 patch alignments (see PROGRESS). `expo-dev-client` is deferred to UP1.
- **Env vars (names only):** client `EXPO_PUBLIC_KINDE_AUDIENCE`; server `KINDE_ISSUER_URL`, `KINDE_AUDIENCE` (required by S1b), `CORS_ORIGINS`, `ANTHROPIC_API_KEY`, `ANTHROPIC_CATEGORIZATION_MODEL`, `ANTHROPIC_ASSISTANT_MODEL`, `AI_DAILY_TOKEN_CAP`, `BB_DEV_DATABASE` (optional, DB0).
- **CI (CI1):** GitHub Actions in each repo (`.github/workflows/ci.yml`, `eval.yml`). Uses `ruby/setup-ruby` and `actions/setup-node` at pinned major versions, and a `postgres:14` service. Repository secret `ANTHROPIC_API_KEY` is needed only for `eval.yml`, and you add it (PO-22).

## 10. Destructive or approval-gated items (none planned)

Nothing in this revision deletes or rewrites existing data. These remain **out of plan** until you approve them separately: dropping `budgets`/`entries`/`tags`/`entries_tags` (PO-10); TD1 orphan cleanup and foreign keys; TD2/TD3; manually linking the 2 existing dev users to Kinde identities (SR-1); migrating the old `bb_server_development` database to the new schema. **Approved in 4.1:** the fresh synthetic-only development database (DB0, PO-11). It's additive; the old database and its backup are kept. **Every commit and every push still needs explicit approval each time**, including the CI workflow files.

## 11. Deferred to v1

Items moved out of the MVP by product-owner decision. Each was decided on the date shown.

| Item | Why deferred | Decided |
|---|---|---|
| **Expo SDK 54 → 58, plus installing Xcode 26.4** | SDK 55+ needs Xcode 26.2+ (56–58: 26.4+, iOS 16.4+); the installed Xcode 16.4 supports up to SDK 54, and the Xcode install (10+ GB) doesn't fit UP1's one-day cap. UP1 stops at SDK 54. | 2026-11-25 |
| **Kinde React Native SDK 1.3.1 → 2.x** | 2.x drops the old bundled Expo modules (uses `react-native-app-auth`) but moves `audience` from the constructor to login: an auth change that needs a KA (Kinde audience check) re-run on the phone. During UP1, 1.3.1 stays, with npm `overrides` so it shares the app's SDK-matched Expo modules (see `ARCHITECTURE.md`). | 2026-11-25 |
| **Ruby 3.3.0 → latest 3.3.x** (`.ruby-version`, `Gemfile`, `Gemfile.lock`, `Dockerfile`, local Ruby), then server CI back to `ubuntu-latest` | Server CI is pinned to `ubuntu-24.04` because the newest runner (Ubuntu 26.04) only has Ruby 3.3.14 and the Gemfile requires 3.3.0. | 2026-11-25 |
| **Keyword rule "CLINIC" → healthcare misfires on vet clinics** (EV1 hard set: WILLOW CREEK VET CLINIC filed as healthcare without review; true category Other). Fix when the rules are next revised, e.g. skip `VET`/`ANIMAL`/`PET` before `CLINIC`, then re-run EV1 and note the rule change in the report. | Keyword rules are frozen for EV1 (fingerprint `9efd9329adcaf092`); changing them now would mean tuning against the hard set. | 2026-11-26 |
