# Budget Buddy — Product Brief

**Status:** APPROVED by product owner (2026-11-22)
**Phase:** 2, Product discovery (summary)
**Traceability:** decisions D-001 to D-012 and constraint C-1 in `claude/DESIGN_DECISIONS.md`

---

## 1. Problem

People who have tried budgeting before, in spreadsheets or apps, usually know _what_ they should do. They stop because:

- keeping records up to date takes constant manual effort;
- a monthly spreadsheet doesn't answer the day-to-day question **"can I cover what's coming, on time?"**;
- money is spread across several places (checking, savings, Venmo, some cash), so no single view shows the whole picture;
- debt costs are easy to ignore, because lenders downplay how much interest adds up.

## 2. Target user

**Primary: the lapsed spreadsheet budgeter.**

- Has tracked spending before (often in Excel), including debt payoff, saving for specific upcoming payments, and saving for bigger purchases.
- Uses several money accounts, each with a fairly distinct purpose (e.g. Venmo for side-job income).
- Understands budgeting terms; doesn't need basic financial education.
- Wants guidance and accountability without the upkeep.

Each user handles money differently. The product learns each user's style instead of assuming one (D-010).

## 3. Value proposition

> **Budget Buddy turns the bank exports you already have into a personal, realistic plan, and an AI coach helps you keep it, one day and one week at a time.**

What makes it different:

1. **No hand-built budget.** You import history; the coach asks a few questions and drafts the plan for you to approve.
2. **Short-horizon planning.** Today and this week, not just "this month", connected to the bills and goals ahead.
3. **Goals as first-class citizens.** Upcoming payments, purchases and debt payoff, each with milestones.
4. **Honest about debt.** Shows what interest is really costing and what paying a bit more would save.
5. **Coach, not judge.** Encourages small changes first; every number is calculated by the app, not guessed by the AI.

## 4. Core concepts (vocabulary)

| Concept               | Meaning                                                                                                  |
| --------------------- | -------------------------------------------------------------------------------------------------------- |
| **Account**           | A source of money data the user imports (checking, savings, Venmo, optional cash), with a stated purpose |
| **Transaction**       | An actual money movement from an import, or a manual cash entry                                          |
| **Transfer**          | Money moving between two of the user's own accounts; excluded from spending and income                   |
| **Category**          | One flat list of spending categories, plus Income and Transfers; optional labels like needs/wants        |
| **Category budget**   | A target amount per category per period                                                                  |
| **Obligation**        | A known upcoming payment with a due date (rent, insurance, debt payment)                                 |
| **Goal**              | Something to build toward: an upcoming big payment, a purchase, or a debt payoff, with milestones        |
| **Financial profile** | What the coach has learned about the user's money style; stored per user, visible and editable           |
| **Plan**              | Category budgets + obligations + goals, drafted by the coach and approved by the user                    |

There is no separate "main budget": **the app is the user's budget** (D-006).

## 5. Core loop

1. **Import** CSV exports from each account (several years is fine).
2. **Tell the app about your accounts**: what each is for; confirm detected transfers; say what savings is for.
3. **Coach interview**: a few targeted questions about income, obligations and goals.
4. **Review the drafted plan**: category budgets, upcoming obligations and goal milestones, with explanations. Approve or adjust (small changes encouraged first).
5. **Plan the next day or week together**, and see where your money goes.
6. **Come back regularly**: re-import, check progress, ask questions, and adjust with the coach.

## 6. Primary views

- **Today / This week** (default home): what's coming up, what's safe to spend, progress on near-term goals.
- **Monthly dashboard**: category budgets vs actuals, where money went.
- Switching between the two is **one tap** (D-003).

## 7. Product principles

1. **The AI proposes; the app calculates; the user decides.** All money figures are deterministic Rails calculations. Nothing is saved without approval.
2. **Private by design.** Each request contains only one user's data; the coach's memory lives in that user's own database rows; synthetic data only during development (D-008).
3. **Honest about freshness.** Every forecast says what date its data runs through (C-1).
4. **Small steps first.** Default suggestions are modest and reversible.
5. **Transparent personalization.** Users can see and correct what the coach believes about them.

## 8. Constraints

- **CSV import only**, with no live bank connection (C-1).
- **Low cost:** inexpensive models, selective AI calls, free or low-cost infrastructure.
- **Existing stack preserved:** Expo/React Native, Zustand, Rails 7.1 API, PostgreSQL, Kinde, Anthropic API through Rails.
- **Timeline:** a 3-day MVP, then about 2 weeks full-time for v1 (D-009).

## 9. Not in scope (whole product, for now)

Live bank connections or aggregators; moving money or making payments; investment advice; tax advice; shared or household budgets; custom model training.

## 10. Carried into Phase 3 (MVP definition)

- **Q-06:** which capabilities ship in the 3-day MVP vs v1.
- **Q-10:** exact contents of the Today / This week view.
- **Q-16:** how much of the financial profile is shown and editable.
