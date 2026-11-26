# Handoff to Claude Code #06 — Milestone 2 build order

**From:** Claude Project
**Date:** 2026-11-25
**Status:** APPROVED by the product owner (2026-11-25). Send it after EV1 (categorization eval, including the harder golden set) and C9 (welcome and account screens) are merged.

## Before you start (product owner)

1. The three M2 specs are approved (2026-11-25):
   - `claude/SPEC_COACH_QA.md` (AS1/AS2 coach Q&A, EV2 coach eval, C4 coach screen), §11 choices already approved;
   - `claude/SCREENS_PLAN.md` (C8 Plan tab), including the **whole-month budget-change correction** in §6;
   - `claude/SPEC_ONBOARDING_PLAN.md` (ON1/ON2 onboarding, PL1/PL2 plan drafting and approval, C5/C6 screens), decisions in §10.
2. Copy into the repo's `docs/product/`: those three specs, `DESIGN_DECISIONS.md`, this file; `GLOSSARY.md` → `docs/GLOSSARY.md`; screenshots into `docs/product/screens/`.
3. Paste the prompt below into Claude Code.

## Milestone 2 goal (MVP_SCOPE §1)

A new user imports, answers a few questions, approves a coach-drafted plan in **under 5 minutes**, and then sees **Left to spend this week**, **bills due**, **goal progress**, and can ask the coach questions whose **figures match the app**.

---

## Prompt for Claude Code

> **Context.** M1 is complete. Build M2 in the order below, one PR per numbered step (or per step and repo), each with green CI and my explicit OK to commit, as before. Specs in `docs/product/`: `SPEC_LEFT_TO_SPEND.md` (approved), `SCREENS_PLAN.md`, `SPEC_ONBOARDING_PLAN.md`, `SPEC_COACH_QA.md`. Where a spec and the built code disagree, tell me before building; real API values win over examples.
>
> **Order (deterministic first, AI on top):**
> 1. **DM-3 category budgets + OB1 bills + G1 goals** (tables, models, owner-scoped APIs, ownership-matrix rows). Budgets by month (`effective_from` = 1st). Bills with structured recurrence, `obligation_payments` per occurrence, day 29–31 → month end. Goals of all three types with `goal_contributions` (set-aside, balance update; undo by delete).
> 2. **G2 goal and debt maths** (`GoalCalculator`, `DebtCalculator`): weekly need, 25/50/75/100% milestones with projected dates, monthly interest, payoff date, total interest, +$X what-if. Hand-calculated test cases; state assumptions in responses.
> 3. **AN1/AN2 spending analytics:** spending summary (with same-length previous period and change), budget vs actual by month (budget in effect on the 1st), category "usual" (median of full months), uncategorized as its own line, confirmed transfers excluded. These are the single source of figures for Home, Plan, onboarding and the coach.
> 4. **W1 Home outlook + C3 Home screen:** exactly `SPEC_LEFT_TO_SPEND.md`, with its §10 worked examples 1–9 as service tests. Home's Month switch opens Plan → Budgets.
> 5. **C8 Plan tab** (`SCREENS_PLAN.md`): Budgets (monthly dashboard, change-a-budget sheet), Bills (add, edit, mark paid, archive), Goals (set aside, update balance, undo).
> 6. **ON1 onboarding questions + C5 screens**, then **ON2 follow-ups** (`SPEC_ONBOARDING_PLAN.md` §3–5, §8).
> 7. **PL1 plan drafting + PL2 approval + C6 approval screen** (§6–7). Include the request-capture test that no merchant names, descriptions or account names reach the model.
> 8. **AS1/AS2 coach Q&A + C4 coach screen** (`SPEC_COACH_QA.md`), including the figure check. Then **EV2 coach eval** (§9): frozen date, golden questions, injection row added to `demo:generate`; report in `docs/evals/`.
> 9. **Q1 end-to-end check:** fresh database → `demo:reset` → full first run on my phone, timed (target < 5 minutes) → Home, Plan, Coach agree on figures.
>
> **If time runs short**, cut in this order (MVP_SCOPE §6): ON2 follow-ups → goal milestones → transfer-to-goal linking → previous-month arrows on Plan. Ask me before cutting anything else.
>
> **Ground rules (unchanged):** additive, reversible migrations; no data rewrites without approval (re-seed with `demo:reset`); no commits or pushes without my explicit OK each time; never print secrets; no financial text in logs; every AI call checks the daily cap; `ARCHITECTURE.md` describes only what's built. Report after each step with test counts, the TypeScript count, any spec deviations, and the exact phone steps for me to check.

---

## What comes back to Claude Project

After each step: deviations from the specs (for the decision log). After step 7: a sample draft plan on demo data (figures and the model's text) for a tone review. After step 8: the EV2 report. After step 9: the timed run and any mismatched figures.
