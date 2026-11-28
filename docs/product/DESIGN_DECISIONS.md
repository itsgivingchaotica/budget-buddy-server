# Budget Buddy — Decision Log & Open Questions

Running log of product and architecture decisions. Explicit decisions by the product owner are recorded separately from Claude's suggestions. **IDs are explained in `claude/GLOSSARY.md`**; per the house rule (D-022), each ID is written with its plain name.

**Status values:** Implemented & verified · Partial / unverified · Proposed (Claude) · Preliminary (owner direction, unconfirmed) · **Approved** (owner explicitly confirmed; source of truth) · Deferred · Superseded

**Reference state (2026-11-25, from Claude Code's reports):** Security S1a–S3, DM-1 through AI2, DEMO-G, S4-min and `demo:reset` (`ec567da`) committed on the server. Client: UP1 Expo upgrade to SDK 54 committed (`7cc9083`); LG1 new tab layout passed the owner's phone check, commit approved. C2, TR1 (transfer matching) and C2b (review and transfer screens) merged to main via PRs with CI; EV1 (categorization eval) built, harder golden set next. MVP runs on a fresh synthetic-only database; the old database is untouched. Project Knowledge does not update automatically.

**Repo copies (updated 2026-11-26):** all project docs now live in the **server repo**, `bb-server/docs/`: product docs in `bb-server/docs/product/` (screenshots in `product/screens/`), `GLOSSARY.md`, `ARCHITECTURE.md`, `PROGRESS.md`, `IMPLEMENTATION_PLAN.md` and `evals/` in `bb-server/docs/`. The client repo (`bb-client`) has no docs folder; its README links to the server repo's docs. Paths written `claude/…` here correspond to `bb-server/docs/product/…` (PO-19).

---

## D-000 — Documentation hierarchy

**Status:** Approved (2026-11-22)

| Document | Role | Maintained by |
|---|---|---|
| `bb-server/docs/ARCHITECTURE.md` | **As-built** record; Claude Code added an "As-built changes since the audit" section (S1a–DM-1) | Claude Code |
| `claude/TARGET_MVP_ARCHITECTURE.md` | **Intended** architecture, with built/designed status labels | Claude Project; Claude Code flags differences |
| `claude/GLOSSARY.md` | One sentence per task ID and ID family | Claude Project |
| `bb-server/docs/IMPLEMENTATION_PLAN.md` | Rev. 4.1 (approved) | Claude Code |
| `bb-server/docs/PROGRESS.md` | Progress log, PO questions, auth status | Claude Code |
| `claude/PRODUCT_BRIEF.md` | Approved Phase 2 summary | Claude Project + owner |
| `claude/MVP_SCOPE.md` | Approved scope with milestones (D-018) | Claude Project + owner |
| `claude/SPEC_LEFT_TO_SPEND.md` | Approved Home outlook spec | Claude Project + owner |
| `claude/SCREENS_ACTIVITY.md`, `claude/SCREENS_WELCOME.md`, `claude/SCREENS_PLAN.md`, `claude/SPEC_COACH_QA.md`, `claude/SPEC_ONBOARDING_PLAN.md` | Screen and feature specs (all approved) | Claude Project + owner |
| `claude/HANDOFF_CLAUDE_CODE_01.md` … `_06.md` | Handoffs (#01, #04 completed; #05 in progress; #06 approved, Milestone 2); #02 and #03 superseded by #04 | Claude Project |
| Design canvas (https://claude.ai/artifact/DkfvXfySAgRetsnG4b9MFf) | Brand page (D-020), "Welcome & account", "Home & onboarding", "Activity", "Coach" and "Plan" screens | Claude Project + owner |
| This log | Decisions and open questions | Claude Project + owner |

---

## Product decisions (Approved 2026-11-22 unless noted)

| # | Decision | Summary |
|---|---|---|
| D-001 | Primary user | Lapsed spreadsheet budgeter (partly the owner). Core job: "can I cover what's coming, on time?" |
| D-002 | Plan creation | Import history → interview → coach drafts plan → user approves; small changes first. Plan = category budgets + obligations + goals. AI proposes, Rails calculates, user decides. MVP interview: structured + light conversation; fully conversational in v1. |
| D-003 | Primary views | Home = Today / This week; monthly dashboard one tap away. Home metric **"Left to spend this week"** (D-018, D-021). |
| D-004 | AI capabilities | Categorization, Q&A, insights, plan suggestions, onboarding interview, coaching tone. Split per MVP_SCOPE. |
| D-005 | First-session aha | Plan the day/week, goal milestones, see where money goes. Forecasting in v1. |
| D-006 | The app is the budget | No named budgets; each category has a budget; goals separate. |
| D-007 | Accounts and transfers | Multiple accounts with purposes; transfers matched and excluded; savings linked to goals (manual in MVP); cash optional (v1). |
| D-008 | Privacy | No per-user agent; stateless calls; user-scoped data; minimization; no financial text in logs; synthetic data only in development. |
| D-009 | Timeline | **Revised by D-018:** two MVP milestones (Days 1–3, Days 4–7), then v1 through day ~14. |
| D-010 | Financial profile | Stored per user from history + answers; visible/editable UI in v1. |
| D-011 | Debt | Balance + APR + payment; deterministic interest, payoff date, total interest, +$X savings; assumptions shown. |
| D-012 | Categories | Flat list + Income + Transfers; optional labels. |
| D-013 | Goals | All three types in MVP (upcoming payment, purchase, debt payoff). |
| D-014 | Success criteria | <5 min sign-up to approved plan; coach figures match views; zero cross-user access; zero duplicates on re-import. |
| D-015 | MVP scope | `claude/MVP_SCOPE.md` approved. |
| C-1 | Constraint | CSV import only; data-through date on every forecast. |

---

## D-016 — Skills to showcase

**Status:** Approved (2026-11-22)

| Skill | Product use | Tier |
|---|---|---|
| LLM API integration, structured outputs, function calling, prompt engineering | Categorization, plan drafting, onboarding follow-ups, coach Q&A | MVP |
| LLM evaluation (lite) | Golden synthetic transactions → categorization accuracy; Q&A cases → right tool + figures match analytics | MVP (categorization eval in M1, Q&A eval in M2) |
| GitHub Actions (minimal CI) | Rails tests + client type-check on every push | MVP (M1) |
| AI-assisted testing | Claude Code drafts tests and edge-case CSVs; developer reviews; documented in README | MVP practice; write-up v1 |
| Docker / Compose | Local dev + CI parity; production image | v1 week 1 |
| AWS pipeline + IAM | GitHub Actions → ECR → deploy; least privilege; OIDC (no stored keys) | v1 week 1 |
| AWS S3 | Expo web build on S3 + CloudFront (clickable demo); encrypted DB backups | v1 week 1 |
| LLM evaluation (full) | Scheduled evals with cost cap; LLM-as-judge for tone; regression history | v1 week 2 |

**AWS budget: under $15/month** (owner, 2026-11-22). Uploaded CSVs are parsed and discarded, not stored.

---

## D-017 — Feasibility review results (handoff #01)

**Status:** Accepted (2026-11-22). Details in `docs/PROGRESS.md` and plan rev. 4.

Scope 56–82 h vs ~24–30 h in 3 days → milestones. Data model: soft-retire budgets; categories additive; new tables owned by the user or through accounts. Generic CSV format and deterministic synthetic demo generator loaded through the real import pipeline.

---

## D-018 — Plan rev. 4 approved with amendments; PO answers

**Status:** Approved (owner, 2026-11-22)

**Milestones:** M1 = Days 1–3, M2 = Days 4–7, then v1.

**Amendments:** (1) AI-0 Claude connection, a minimal S4 rate limits and AI cost cap, and AI2 Claude categorization move into M1; TR1 transfer matching slips to M2 if needed. (2) Home metric "Left to spend this week". (3) Tabs Home, Plan, Activity, Coach. (4) Minimal CI in M1; eval-lite in M1 (categorization) and M2 (Q&A).

**PO answers:** PO-1 scope approved · PO-4 obligation = from cash flow, upcoming-payment goal = saved ahead; emergency fund = undated purchase goal · PO-5 income pattern on profile, manual mark-paid · PO-6 budget-based formula · PO-7 global read-only labels · PO-8 one Income + Insurance + Other · PO-9 card payments = Debt Payments unless confirmed transfer · PO-10 hide legacy tabs, scope legacy endpoints, drop tables only in v1 with approval · PO-11 fresh synthetic-only dev DB · PO-12 per-user week start/time zone (default Monday, device tz) · PO-13 monthly budgets only · PO-14 `plan_proposals` approved · PO-15 10,000 rows / 2 MB · PO-16 3-day window, different accounts · PO-17 credit cards allowed · PO-18 CSV format approved · PO-19 repo copies in `docs/product/` · PO-20 S1a approved.

---

## D-019 — Navigation, first run and mascot (Phase 4)

**Status:** Approved (owner, 2026-11-22)

Tabs Home, Plan, Activity, Coach. First run: accounts and import → coach interview → top 3–5 merchants → approve plan → Home. Squirrel as logo and coach avatar.

---

## D-020 — Brand

**Status:** Approved (owner, 2026-11-22); mascot update approved 2026-11-25

Logo A · Acorn Keeper. Palette "Forest Floor": Pine #2F5D46, Moss #7A9A5B, Fern #DCE6D2, Birch #F6F1E7, Acorn #B5652E, Chestnut #8E4A1F, Bark #3A2A1E, Ember #C0563A. Type: Bricolage Grotesque + Inter. Mascot only in onboarding, coach avatar, empty states, celebrations (Proposed). Logo polish in v1.

**Mascot update (Approved, owner, 2026-11-25):** the Acorn Keeper squirrel is redrawn in a cuter style the owner chose: big eyes with highlights; head turned about 45° toward the viewer (two ears, two eyes); a tall S-curve tail; flat cartoon shapes in Acorn and Chestnut with a cream belly and muzzle; still holding an acorn. Applied on the canvas to the logo, lockup, app icon, small sizes, coach avatar, Home "no plan", onboarding and Welcome screens. The Logo B and C boards are rejected concepts and keep the old drawing. Source files: `bb-client/assets/brand/mascot.svg`, app icon `bb-client/assets/images/app-icon-1024.png`.

---

## D-021 — Home outlook spec

**Status:** Approved (owner, 2026-11-24). Spec: `claude/SPEC_LEFT_TO_SPEND.md`.

Left to spend over the calendar week; uncategorized counts as spending; conservative rounding; states `no_plan` > `stale` > `no_data_this_week` > `ok`; bills over the rolling next 7 days; mark paid per bill occurrence.

---

## D-022 — Schema design, build order and naming rule

**Status:** Schema and DM-1 design approved; S3 commit approved (owner, 2026-11-24). Build order followed; UP1 resolved (Q-36).

- **Schema (Claude Code's design, 2026-11-24):** reviewed by Claude Project, no conflicts with D-000–D-021. Recorded in `TARGET_MVP_ARCHITECTURE.md` §3. Confirmations: `week_starts_on` uses Ruby day numbers (1 = Monday, default); new categories leave `category_type` NULL so the old app's `categories#default` is unchanged; `need_want` and `recurrence_label` defaults accepted.
- **Build order (PO-33):** TS0 TypeScript baseline → C0 app sends the login token → DM-2 accounts and onward. Reason: the current app gets 401 on every call until C0, and C0 doesn't depend on UP1.
- **UP1 Expo upgrade (Approved, 2026-11-25):** SDK 51 → 54 in M1, one SDK at a time; SDK 54 is the newest that works with Xcode 16.4. Kinde 1.3.1 kept with a shared-module workaround (documented in `ARCHITECTURE.md`); Storybook removed; NativeWind 2 → 4. v1 list: SDK 54 → 58 plus the Xcode 26.4 install; Kinde 2.x upgrade.
- **Naming rule (owner request, 2026-11-24):** every task ID or question ID in docs and messages is written with a plain name the first time, e.g. "DM-1 (new category list)". Glossary: `claude/GLOSSARY.md`. Claude Code to follow the same rule.

---

## D-023 — Welcome (signed-out) screen and log out

**Status:** Approved (owner, 2026-11-25). Spec: `claude/SCREENS_WELCOME.md` (C9 welcome and account screens).

- **Welcome:** Option A "forest morning" on the canvas page "Welcome & account": light Birch screen; forest-clearing illustration with the mascot on a tree stump beside a jar of saved acorns; two-tone "Budget / Buddy" name; tagline from the brief; Pine "Sign in" and outlined "Create an account"; one-line Terms and Privacy. Option B "Buddy note" (dark Pine, mascot on a banknote) kept on the canvas as a rejected alternative.
- **After sign-in:** no accounts → Activity tab (first run); otherwise Home.
- **Sign-in and create-account forms** stay Kinde's hosted pages; the owner brands them in the Kinde dashboard (logo, colours).
- **Log out:** moves from the Home placeholder to an account sheet opened from the user's initial on Home; no confirm dialog.

---

## D-024 — Finish M1: transfer matching, review and undo (handoff #05)

**Status:** Approved (owner, 2026-11-25). Contracts: `claude/HANDOFF_CLAUDE_CODE_05.md` §A–C.

- **Order:** TR1 (transfer matching) → C2b (review and transfer screens) → CI1 (GitHub Actions CI) → EV1 (categorization eval) → C9 (welcome and account screens).
- **TR1:** deterministic pairs (same user, different accounts, equal and opposite amounts, ≤ 3 days); one link per transaction; rejected pairs never re-suggested; confirm stores the rows' previous state so Undo restores it; Transfers set only by a confirm.
- **`suggested_category_id`:** Claude's low-confidence guess, shown as a "Name?" chip; does not count as categorized until confirmed; never Transfers.
- **Undo a category fix:** new `category_corrections` table storing each affected row's previous state and the merchant rule's previous state; undo restores only rows still in the corrected category. Chosen over a client re-send, which would leave merchant memory and the other updated rows wrong (owner chose the table, 2026-11-25).
- **Review list:** one server summary grouped by merchant, with the suggestion and up to two deterministic alternatives (no AI call).
- **Import:** upload starts only on an explicit **Import** tap after choosing account and file (no undo for imports in MVP).

---

## D-025 — Coach Q&A choices and Plan tab

**Status:** Approved (owner, 2026-11-25).

- **Coach Q&A (`SPEC_COACH_QA.md`, approved):** chat history in memory only; merchant questions via `merchant_contains`; `get_week_outlook` as the fourth read-only tool; the figure check.
- **Plan tab (`SCREENS_PLAN.md`):** budgets can be edited in the MVP; Plan → Budgets is the monthly dashboard (P9), opened by Home's Month switch; "+ Add a bill" in the MVP; goals created only in onboarding, "+ Add goal" in v1.
- **Correction (Approved):** a budget change applies to the **whole current month** (`effective_from` = the 1st, as the approved schema requires), not "from this week". No visible difference in the MVP.
- **Mascot detail (Approved):** the full-size mascot holds a small green dollar bill behind the acorn; tiny icon sizes and the round coach avatar keep the simpler drawing.

---

## D-026 — Onboarding, plan drafting, EV1 rigour and Milestone 2 order

**Status:** Approved (owner, 2026-11-25). Specs: `claude/SPEC_ONBOARDING_PLAN.md`; handoff `claude/HANDOFF_CLAUDE_CODE_06.md`.

- **Follow-ups (ON2)** from a fixed menu of slots: Claude picks at most 2 and words them; Rails owns the options; any AI failure skips them.
- **No digits in model text** for plan drafting (PL1): every figure on screen comes from Rails; invalid output → one retry → deterministic fallback.
- **Budget options:** keep = usual rounded up to $5; trim = 10% less; stretch = 20% less (only for "Push me a bit"; never for Groceries, Healthcare, Transportation); at most 3 trims for "Small trims".
- **Likely-bill detection in onboarding** (same merchant, fixed category, 2 of 3 months, ±10%, ±3 days) pre-fills the bills question; full recurring detection stays v1.
- **Privacy:** no merchant names, descriptions or account names in any model request (request-capture test).
- **EV1 (categorization eval):** the first run scored 100% mostly because the keyword rules were written alongside the demo data. Add a hand-written hard golden set (labels set at authoring, keyword rules frozen) and a Claude-only run; the GitHub `workflow_dispatch` eval job is deferred to v1.
- **Milestone 2 order (handoff #06):** budgets/bills/goals → goal and debt maths → analytics → Home → Plan tab → onboarding → plan drafting and approval → coach and EV2 → timed end-to-end run.

---

## D-027 — Deterministic first, AI as assistant (engineering principle)

**Status:** Approved (owner, 2026-11-26), including the three changes below.

Following advice from an experienced AI engineer: build scripts and deterministic systems first, use AI to connect and assist them, and make sure the developer understands and verifies what gets built. Budget Buddy already follows the core rule (D-002 "AI proposes, Rails calculates, user decides"); this makes it a standing rule for every feature.

**The split in Budget Buddy:**

| Deterministic code decides | AI assists |
|---|---|
| CSV parsing, duplicate detection, import limits | — |
| Transfer matching (suggestions; user confirms) | Second safety net: low confidence on transfer-like rows sends them to review |
| Keyword rules and merchant memory | Categorizing rows the rules don't know, from a fixed list, with a confidence score |
| Budget options, income check, Left to spend, bills, goal and debt maths | Choosing among Rails-computed options and explaining them (no digits in its text) |
| Onboarding facts (pay pattern, side income, likely bills) | Picking and wording ≤ 2 follow-up questions from a fixed menu |
| Analytics answering coach questions; the figure check | Understanding the question, picking read-only tools, wording the answer |
| Access control, rate limits, AI cost cap | — |

**AI feature contract** (every AI feature must state all of these in its spec): inputs (and what is deliberately excluded); what the AI decides; what code decides; validation of the output; fallback when it fails; how it's evaluated (labels independent of the system); what's logged (no financial text).

**Changes (Approved 2026-11-26):**
1. **Show where a category came from.** Rows categorized by Claude without review get a small "by coach" marker in Activity, and a filter to review them (with C8 or as a small follow-up to C2b, Claude Code's choice). The user can always see and override AI decisions, not just uncertain ones.
2. **Understanding check per PR.** Each PR report from Claude Code lists the 2–3 files that hold the core logic, a plain-language walkthrough, and 3 questions the owner should be able to answer. The owner reads those files before approving. Started with the G2 (goal and debt maths) PR.
3. **Figures audit script for Q1.** A rake task that computes the same figures through Home, Plan and the coach's tools for the demo user and fails if any differ. Built in step 9 (Q1 end-to-end check).

---

## D-028 — Uncategorized money in, refunds across categories, unbudgeted spending

**Status:** Approved (owner, 2026-11-26). Raised by Claude Code while building AN1/AN2 (spending analytics).

- **Uncategorized rows count only money going out** (Home, Plan and the coach alike). The original `SPEC_LEFT_TO_SPEND.md` §3.2 netted all flexible and uncategorized rows, so an uncategorized paycheck could cancel a week's spending. Spec amended (§2, §3.2, §4.2) with worked examples 10–11.
- **Each flexible category floors at $0 separately**, so a refund in one category can't offset spending in another.
- **Unbudgeted spending:** budget vs actual lists flexible categories with spending but no budget; the Plan tab shows them in a "No budget yet" group where tapping one sets a budget (`SCREENS_PLAN.md` §3).
- **Other AN1 choices accepted:** "near" = 90% or more spent ($0 budget with spending = over); API range 366 days, service 24 months (coach); the context endpoint takes an optional `amount`; change percent to one decimal, omitted when the previous period had no spending.

---

## D-029 — Ambition level (project-build-workflow)

**Status:** Approved (owner, recorded by the Builder 2026-11-27).

**L0 (portfolio / learning), designed for L1 (private beta).** Synthetic demo data only; build what L0 needs, and make hard-to-reverse choices (money as decimal, time in UTC shown in the user's zone, user-owned data, hosted auth) so a move to L1 doesn't need a rewrite. Recorded as D-029 because D-001 was already taken.

---

## D-030 — Trim follow-up threshold (ON2)

**Status:** Approved (owner, 2026-11-28). Decision issue: server #38.

The `biggest_trim_ok` follow-up is eligible only when the top everyday category's usual spending is **≥ 120%** of its lowest recent month.

---

## D-031 — Onboarding as built (ON1, ON2, C5)

**Status:** Approved (owner, 2026-11-27/28). Merged: server #33, #35; client #29, #32.

- **C5:** tapping an earlier answer bubble reopens that question; the bills checklist always lists every detected bill, with removed ones unticked (owner's option 2).
- **ON2 failures:** a successful follow-up result (even "none") is stored; a failure (refusal, outage, AI cap) is **not stored** and is retried next time. Onboarding never blocks on AI.
- **ON2 client:** earlier answers aren't tappable during the follow-ups (accepted; a "change earlier answers" link is client #36, M3).
- **Prefill:** comes from `GET /onboarding` (`questions[].prefill`), as SPEC_ONBOARDING_PLAN §4 describes; the issue text naming `/onboarding/context` was wrong.
- **Spec-order and scope choices accepted** (ON1 report): pay question first; no free-text boxes; no week-start or time-zone questions; date chips instead of a date picker (with a "No date" option for undated goals).
- **K-1 (CI test timeout):** Jest limit raised to 20 s on CI; onboarding tests wait for each step (client #34).

---

## D-032 — Plan drafting and approval details (PL1, PL2, C6)

**Status:** Approved (owner, 2026-11-28). Raised by the Builder before PL1; spec amended (`SPEC_ONBOARDING_PLAN.md` §6.2, §6.4, §7).

1. **Income:** data median, unless the user changed the paycheck amount in question 1 (then amount × paychecks per month, same monthly-average function as bills).
2. **Irregular pay without a stated floor:** the **lowest** of the last 3 full months ("Based on your lowest recent month"), not the median.
3. **Debt payment:** counted as committed unless a kept bill is in Debt Payments.
4. **Existing rows at approval:** this month's budgets replaced only for categories in the draft; duplicate-named bills and goals skipped and listed in the response.
5. **Rent from "Add it":** median Rent spending of the last 3 full months, on the usual day, labelled "from your spending", editable.
6. **Goal order:** the user's order wins; the model's only when they didn't answer.
7. **Statuses:** `draft` / `approved` / `superseded`, stale computed on read; a second approve → 409 `already_approved`, treated as success by the app.
8. **Three PRs:** PL1 #24 → PL2 #25 → C6 #20.

---

## D-033 — Plan fallback for "Push me a bit"

**Status:** Approved (owner, 2026-11-28). Raised in the PL1 (plan drafting) review; spec amended (`SPEC_ONBOARDING_PLAN.md` §6.3).

- When the model fails twice, refuses, is unavailable or the AI cap is reached, "Push me a bit" falls back like "Small trims": **trim the 2 largest non-essential categories that have a trim**. The fallback never gives less change than the user asked for; stretch stays model-only; "Keep things as they are" keeps everything.
- **Unknown categories in the model's answer stay strict:** the check fails → one retry → fallback (not silently dropped).

---

## D-034 — Plan draft honesty and display (PL1 tone review)

**Status:** Approved (owner, 2026-11-28). From the Planner's review of the PL1 sample draft on demo data; spec amended (`SPEC_ONBOARDING_PLAN.md` §4.1, §6.3, §6.5).

1. **At least one change when asked:** for "Small trims" and "Push me a bit", at least one non-keep option whenever a non-essential category has a trim (still ≤ 3 trims). If no trim exists, the model is told so and the intro must not claim changes. (The sample kept everything while its intro said "Small changes only".)
2. **Unplanned money and undated goals on C6:** show "Unplanned each month: $X" (Rails figure); undated goals show "No date set · add a date to get a weekly amount" with an Add a date action, never "$0.00 a month". (The sample left $1,690/month unplanned while two goals got $0.)
3. **Tidy bill names at detection** (Title Case, common bank noise removed; raw merchant key kept for matching; editable). Built as a small separate fix PR.
4. **Rounding unchanged** (keep rounds up to $5); C6 shows "Your usual" in whole dollars.

**Where each lands:** 1 in PL1 before its PR (sample re-run); 3 as its own fix PR; 2 and 4 in C6.

---

## Open questions register

| # | Question | Phase | Status |
|---|---|---|---|
| Q-08 | Insights: deterministic rules + AI wording, or LLM-selected? | 8 | Open (v1) |
| Q-17 | Re-import cadence and nudges | 4 | Open (v1) |
| Q-34 | Screen-by-screen journey and layouts for each tab | 4/6 | Resolved for the MVP: all four tabs, Welcome and onboarding designed; specs approved |
| Q-36 | UP1 Expo upgrade: do it in M1 before the new screens, or defer to v1? | 7 | **Resolved 2026-11-25:** SDK 54 in M1 (`7cc9083`); SDK 54 → 58 + Xcode 26.4 and Kinde 2.x in v1 |

Resolved: Q-01–Q-07, Q-09–Q-16, Q-18–Q-33, Q-35 (auth status reported), Q-36.
