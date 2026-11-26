# Budget Buddy — Glossary of IDs and terms

One sentence per ID, so docs and messages can be read without cross-referencing.
**House rule (2026-11-24):** whenever an ID appears in a doc or message, write its plain name next to it the first time, e.g. "DM-1 (new category list)".
**Repo copy:** `docs/GLOSSARY.md` (Claude Code's location). Status marks: ✅ committed · 🟡 built, not committed.
**Last updated:** 2026-11-25 evening (C2 passed the phone test; spec links added).

---

## ID families

| Prefix | Meaning | Where they live |
|---|---|---|
| **D-0nn** | A product or architecture **decision** (e.g. D-021 = Home outlook spec) | `DESIGN_DECISIONS.md` |
| **C-1** | A hard **constraint** (CSV import only, no live bank link) | `DESIGN_DECISIONS.md` |
| **Q-nn** | An **open question** in the Claude Project register | `DESIGN_DECISIONS.md` |
| **PO-nn** | A **question for the product owner** raised by Claude Code (e.g. PO-33 = build order) | `docs/PROGRESS.md` |
| **P1–P10** | The 10 **MVP features** in priority order | `MVP_SCOPE.md` |
| **M1 / M2** | **Milestone 1** (Days 1–3: secure foundation, import, categorization) and **Milestone 2** (Days 4–7: plan, goals, Home, coach) | `MVP_SCOPE.md` |
| **SR-1** | **Security requirement 1:** never link an existing account to a Kinde login on an unverified email | Implementation plan |
| **TD1–TD5** | Known **technical debt** accepted for the MVP | Implementation plan |
| **K1–K14** | **Known issues** found in the Copilot-era code | `docs/PROGRESS.md` |
| **X1–X13** | **Mismatches** between the old plan and the code, found in the audit | `ARCHITECTURE.md` |
| **Task IDs** (below) | One reviewable piece of build work | Implementation plan |

## Build tasks

### Security and setup
| ID | Plain name | One sentence |
|---|---|---|
| S1a | Token checker | Rails code that verifies a Kinde login token is genuine and unexpired. ✅ |
| KA | Kinde API audience | Registering the API in Kinde so login tokens say they're meant for our server. ✅ |
| S1b | Require login | Every API endpoint rejects requests without a valid token. ✅ |
| S2 | `/me` and user linking | The server finds or creates your user record from your Kinde login. ✅ |
| S3 | Ownership rules | Each user can only reach their own data; others' data acts as if it doesn't exist. ✅ |
| S3-L | Legacy endpoint rules | The same ownership rules applied to the old budgets/entries/tags endpoints. ✅ |
| S4 | Rate limits and AI cost cap | Limits on how often endpoints and AI features can be called, plus a daily AI token cap. |
| S4-min | Minimal rate limit and AI cost cap | The M1 slice of S4: a limit on the categorize endpoint plus the daily AI token cap. ✅ |
| DB0 | Fresh dev database | A new, synthetic-data-only development database; the old one is kept untouched. ✅ |
| TS0 | TypeScript baseline | Records the app's existing TypeScript errors so new work can't add more (now 48). ✅ |
| C0 | App sends the login token | The app attaches your token to every API call, retries once on 401, else returns to login; uses `/me`. ✅ |
| CT0 | Client test setup | Make the app's test runner (Jest) work. |
| CI1 | GitHub Actions CI | Runs server tests and the client type check automatically on every push. |
| UP1 | Expo upgrade | Upgraded the app from Expo SDK 51 to SDK 54 (React Native 0.81, NativeWind 4); SDK 58 is v1. ✅ |
| LG1 | New tab layout | Hide the old screens and add the Home, Plan, Activity and Coach tabs. (Commit approved 2026-11-25.) |

### Data and import
| ID | Plain name | One sentence |
|---|---|---|
| DM-1 | New category list | Adds the flat list of 17 spending categories plus Income and Transfers, with everyday/fixed labels. ✅ |
| DM-2 | Accounts | The table and API for your checking, savings, Venmo and other accounts; deleting archives. ✅ |
| DM-3 | Category budgets | The table and API for monthly budgets per category. |
| T1 | Transactions tables | The tables that store imports and every imported transaction. ✅ |
| I1 | CSV reader | Reads the generic CSV format and reports bad rows by line number. ✅ |
| I2 | Import endpoint | Upload a CSV to an account, skip duplicates, list and edit transactions. ✅ |
| TR1 | Transfer matching | Suggests pairs of transactions that are money moving between your own accounts (contract: handoff #05 §A). |
| DEMO-G | Demo data generator | Creates realistic fake CSVs for the demo user (checking, savings, Venmo), including decoy pairs to test Reject; `demo:reset` resets the demo user. ✅ |

### Categorization and AI
| ID | Plain name | One sentence |
|---|---|---|
| AI-0 | Claude connection | Adds the Anthropic SDK and proves one real call works. ✅ |
| AI1 | Categorization pipeline | Tries merchant memory, then keyword rules, before any AI. ✅ |
| AI2 | Claude categorization | Claude categorizes whatever rules couldn't, choosing only from the allowed list; transfer-like rows go straight to review. ✅ |
| AI3 | Learn from corrections | When you fix a category, the app remembers that merchant. ✅ |
| EV1 | Categorization eval | Measures how accurately categorization labels a fixed set of fake transactions. |
| EV2 | Coach Q&A eval | Checks the coach calls the right tool and its figures match the app's (spec: `SPEC_COACH_QA.md` §9). |
| ON1 | Onboarding questions | The structured tap-to-answer interview and your saved answers. |
| ON2 | Coach follow-ups | Claude asks up to 2 follow-up questions based on your answers. |
| PL1 | Plan drafting | Rails computes candidate budgets, bills and goals; Claude picks and explains them. |
| PL2 | Plan approval | Approving the draft saves all budgets, bills and goals in one step. |
| AS1 | Coach Q&A | Ask questions; Claude answers using read-only tools that only see your data (spec: `SPEC_COACH_QA.md`). |
| AS2 | Coach Q&A limits | Caps on chat history length and tool output, and no chat text in logs. |

### Calculations
| ID | Plain name | One sentence |
|---|---|---|
| OB1 | Bills | The bills table, due-date schedule, and "mark paid" per occurrence. |
| AN1 | Spending analytics | Totals, budget vs actual, and category averages, with transfers excluded. |
| AN2 | Analytics endpoints | The API endpoints for AN1's figures. |
| G1 | Goals | The goals and contributions tables and API. |
| G2 | Goal and debt maths | Weekly amounts needed, milestones, interest cost and payoff dates. |
| W1 | Home outlook | Left to spend this week, bills in the next 7 days, and this week's goal contributions. |

### App screens
| ID | Plain name | One sentence |
|---|---|---|
| C2 | Accounts and import screens | List and add accounts, upload CSVs, see the import summary. 🟡 Passed the owner's phone test 2026-11-25; commit pending. |
| C2b | Review and transfer screens | Fix uncertain categories (with Undo) and confirm suggested transfers. |
| C3 | Home screen | Left to spend, bills, goals; Home's Month switch opens Plan → Budgets. |
| C4 | Coach chat screen | Ask the coach questions (spec: `SPEC_COACH_QA.md` §8). |
| C5 | Onboarding screens | The first-run interview flow. |
| C6 | Plan approval screen | Review and approve the drafted plan. |
| C7 | Goals screens | Goal progress, milestones and the debt interest view (in the Plan tab's Goals section). |
| C8 | Plan tab screens | The Plan tab: category budgets (also the monthly dashboard), bills and goals (spec: `SCREENS_PLAN.md`). |
| C9 | Welcome and account screens | The signed-out Welcome screen, the account sheet with Log out, and the new app icon (spec: `SCREENS_WELCOME.md`). |
| CT | Client tests | Tests for the app's key logic and screens. |
| Q1 | Bug-fix and end-to-end check | Run every test and a full manual run on a fresh database. |
| DEMO | Portfolio packaging | README, architecture diagram, demo script. |

## Other terms

| Term | Meaning |
|---|---|
| **Left to spend** | This week's share of your everyday budgets minus what you've spent in them (spec: `SPEC_LEFT_TO_SPEND.md`). |
| **Everyday / flexible category** | A category labelled `variable` (e.g. Groceries); counts toward Left to spend. |
| **Fixed category** | A category labelled `fixed` (e.g. Rent); shown as bills instead. |
| **Obligation** | A bill paid from regular income, with a due date. |
| **Legacy** | Old tables and screens (budgets, entries, tags) kept frozen until removed in v1. |
| **As-built vs target** | `docs/ARCHITECTURE.md` = what exists; `TARGET_MVP_ARCHITECTURE.md` = what we intend. |
| **Slug** | A stable text key for a category, like `groceries` or `dining-out`, used instead of database IDs. |
| **Ownership matrix** | A table-driven test where one user tries to read or change another user's data; every row must be refused. |
| **SDK (Expo)** | A numbered, tested set of React, React Native and Expo module versions released together (e.g. SDK 54). |
| **Figure check** | The coach's safeguard: every amount in an answer must match a tool result, or it's corrected or replaced (spec: `SPEC_COACH_QA.md` §5). |
| **Decoy pair** | Demo transactions that look like a transfer but aren't (e.g. a Venmo repayment and a same-amount Ticketmaster charge), used to test Reject. |
