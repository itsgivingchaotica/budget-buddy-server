# Budget Buddy — Demo script and interview prep

**Status:** DRAFT (2026-11-25). Update after the Milestone 2 end-to-end run (Q1); steps marked (M2) need Milestone 2.
**Setup before any demo:** `demo:reset` (fresh demo user and imports); phone charged, on the same Wi-Fi as the Mac; Rails and Metro running; if the free signing certificate is older than 7 days, reinstall with ▶ in Xcode; airplane-mode test done once beforehand so you know the error screens work.

---

## The 3-minute demo

| Time | Show | Say (in your own words) |
|---|---|---|
| 0:00 | **Welcome screen** → Sign in | "Budget Buddy turns the bank exports you already have into a plan you can actually keep. Sign-in is Kinde; the API checks every token." |
| 0:15 | **Activity** → Import `checking-overlap.csv` | "Re-importing an overlapping export adds nothing: 76 duplicates skipped. The file is read and thrown away." |
| 0:35 | **Review** → pick a category for one merchant → **Undo** | "Rules and memory handle most rows; Claude handles the rest, and anything it isn't sure about comes here. One tap fixes a whole merchant and teaches the app. Undo puts everything back, including what it learned." |
| 1:00 | **Transfers** → Confirm a savings transfer → Reject the "concert tickets" pair | "Money moving between my own accounts isn't spending. The app suggests pairs; this one is a decoy, a friend paying me back. The app suggests, I decide." |
| 1:25 | (M2) **Home** | "Left to spend this week is based on my budgets, not a bank balance, because CSVs don't give a reliable balance. Bills for the next 7 days are listed separately." |
| 1:45 | (M2) **Plan** → Goals | "The debt maths (interest, payoff date, what $50 more a month saves) is plain Ruby with hand-calculated tests. The AI never does arithmetic." |
| 2:05 | (M2) **Coach** → "How much did I spend on dining out this month?" | "The coach can only call four read-only tools scoped to me. Every number in its answer is checked against the tool results before I see it. Here's what it was based on." |
| 2:30 | (M2) **Coach** → "Should I put my savings into crypto?" | "And it knows its limits." |
| 2:40 | **GitHub**: the EV1 report and a merged PR with green CI | "I measured it: 96.8% on a hand-written hard set, zero transfers miscategorized. The easy set scored 100%, but I wrote the rules alongside that data, so I built a harder one." |
| 3:00 | — | "Happy to go deeper on any part." |

**If something fails live:** say what you'd expect to see, show the matching screenshot in `docs/product/screens/`, and move on. A calm recovery reads well.

## Interview questions to prepare

1. **"Why not let the LLM calculate the budget?"** Money must be exact and testable. The model is good at choosing and explaining, so Rails computes every candidate figure and the model picks among them. For the plan, its text can't even contain digits.
2. **"How do you stop the coach making up numbers?"** Read-only tools return existing service output; a figure check compares every amount in the answer with the tool results; one correction attempt, then a deterministic fallback. Measured in the coach eval (EV2).
3. **"How do you know categorization works?"** Offline eval with labels that never come from the pipeline, a hand-written hard set, frozen keyword rules (fingerprinted), and a Claude-only run. The key metric is accuracy of rows the user never reviews.
4. **"How is one user's data protected from another?"** Every query starts from the signed-in user; other users' records act as if they don't exist (404); a table-driven ownership-matrix test covers every endpoint, including the AI tools.
5. **"What about prompt injection?"** Transaction text is treated as data in prompts; the coach eval includes a transaction description that tries to give instructions; tools can't write anything.
6. **"What did you trade off for the MVP?"** CSV only (no live bank link); manual "mark paid"; stateless coach; conversational onboarding and deployment are v1.
7. **"How did you use AI to build it?"** Specs and decisions in a Claude Project; implementation in Claude Code; I approved every spec and every commit; mutation checks to make sure tests actually catch bugs; one PR per feature with CI.
8. **"What would you do next?"** Deploy on AWS within $15 a month, real bank CSV formats, recurring-bill detection, saved coach history, an LLM-judge eval for tone.
9. **"What was the hardest bug?"** Pick a real one from `PROGRESS.md`. Good candidates: the Kinde library bundling its own copies of Expo modules during the SDK upgrade, or merchant corrections that could have silently recategorized a pending transfer.
10. **"Why Haiku?"** Cheap and fast for narrow, structured tasks; the whole hard-set eval cost under a cent; the model id is configurable per feature.
