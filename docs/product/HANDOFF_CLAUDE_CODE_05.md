# Handoff to Claude Code #05 — Finish Milestone 1

**From:** Claude Project
**Date:** 2026-11-25
**Status:** APPROVED by the product owner (2026-11-25). Send it once the C2 (accounts and import screens) phone test has passed and C2 is committed.

## Before you start (product owner)

1. Finish the C2 phone test and approve the C2 commit (client and server).
2. Copy the current versions of these into the repo's `docs/product/` folder:
   - `claude/DESIGN_DECISIONS.md` (now up to D-023)
   - `claude/SCREENS_ACTIVITY.md` (unchanged; listed for completeness)
   - `claude/SCREENS_WELCOME.md` (already there, check it's the latest)
   - `claude/HANDOFF_CLAUDE_CODE_05.md` (this file)
   - `claude/GLOSSARY.md` → `docs/GLOSSARY.md`
3. Paste the prompt below into Claude Code.

## What's left in M1 (Milestone 1)

| Order | Task                                                                     | Status before this handoff                                          |
| ----- | ------------------------------------------------------------------------ | ------------------------------------------------------------------- |
| 1     | TR1 (transfer matching)                                                  | Not started; transfer-like rows already go straight to review (AI2) |
| 2     | C2b (review and transfer screens), with `suggested_category_id` and Undo | Designed (`SCREENS_ACTIVITY.md` §5–6); decisions recorded           |
| 3     | CI1 (GitHub Actions CI)                                                  | Not started                                                         |
| 4     | EV1 (categorization eval)                                                | Not started                                                         |
| 5     | C9 (welcome and account screens)                                         | Spec approved 2026-11-25                                            |

**Approved (owner, 2026-11-25):** all contracts in §A–C, including the `category_corrections` table for Undo (§B.2). Claude Code: if you see a simpler design that keeps the same behaviour, propose it before building.

---

## Prompt for Claude Code

> **Context.** C2 is committed. Finish M1 in this order: **TR1 → C2b → CI1 → EV1**, then **C9** (welcome and account screens; `docs/product/SCREENS_WELCOME.md` is approved). Contracts for TR1 and C2b are in `docs/product/HANDOFF_CLAUDE_CODE_05.md` §A–C; read them before starting. Report after each task with test counts, the TypeScript count, and what's uncommitted. Ground rules as always: additive, reversible migrations; no data rewrites without approval (use `demo:reset` to re-seed instead); no commits or pushes without my explicit OK each time; never print secrets or financial text in logs; `ARCHITECTURE.md` describes only what's built.

---

## A. TR1 (transfer matching): contract

**Purpose:** suggest pairs of transactions that are money moving between the user's own accounts, so they're left out of spending and income once confirmed (MVP_SCOPE P3).

**Matching rule (deterministic, PO-16):**

- Same user; **different accounts**; amounts equal and **opposite sign**; dates **≤ 3 days apart**.
- Neither row is already in a `suggested` or `confirmed` link, and the pair hasn't been **rejected** before (unique index on the ordered pair).
- If one row has several candidates: prefer the smallest date gap, then the earliest candidate by date, then lowest id. Each transaction belongs to at most one suggested or confirmed link.
- Run after every successful import, for that user, over rows within ±3 days of the imported date range. Must be idempotent: running twice creates nothing new.

**States and effects:**

| Action  | Endpoint                                      | Effect (one DB transaction)                                                                                                                                                                                       |
| ------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| List    | `GET /api/v1/transfer_links?status=suggested` | Pairs with both transactions (account name, date, description, amount) and `days_apart`                                                                                                                           |
| Confirm | `POST /api/v1/transfer_links/:id/confirm`     | Link → `confirmed`; both rows get the Transfers category and `needs_review = false`; **store each row's previous `category_id`, `needs_review` and `suggested_category_id` on the link** so Undo can restore them |
| Reject  | `POST /api/v1/transfer_links/:id/reject`      | Link → `rejected` (kept, so the pair is never suggested again); rows untouched, stay in review                                                                                                                    |
| Undo    | `DELETE /api/v1/transfer_links/:id`           | Confirmed → restore both rows from the stored values, link back to `suggested`. Rejected → back to `suggested`.                                                                                                   |

- All scoped through `current_user`; another user's link is a 404 (add rows to the ownership matrix).
- Transfers can **only** be set by a confirm; `PATCH /transactions/:id` must keep refusing the Transfers category.
- A transfer-like row with no match (e.g. money sent to an account the user didn't import) stays in review for the user to categorize normally.

**Tests:** matching rule edge cases (exactly 3 days, 4 days, same account, same sign, already rejected, one row with two candidates), idempotency, confirm/reject/undo effects, ownership.
**Acceptance with demo data:** after `demo:reset` and TR1, report the number of suggested pairs and the remaining "to review" count. I expect about 54 real pairs plus up to 8 DEMO-G decoy pairs (there to test Reject), and roughly 36 rows left to review; explain any difference rather than tuning the data.

---

## B. C2b (review and transfer screens): server contracts

### B.1 `suggested_category_id` (decision recorded 2026-11-25)

- Additive nullable FK on `transactions` → `categories`.
- **Set by AI2** when Claude's confidence is below 0.6: the row gets `needs_review = true`, `category_id = NULL`, and `suggested_category_id` = Claude's pick. Never the Transfers category.
- Rules (merchant memory, keywords) never need it: they either categorize or leave both empty.
- Cleared when the row is categorized (by the user, a merchant rule, or a confirmed transfer).
- A suggestion **does not count as categorized**: it stays out of budgets and analytics until confirmed.
- Existing review rows aren't backfilled; `demo:reset` produces fresh rows with suggestions.

### B.2 Undo a category correction (Approved by the owner, 2026-11-25: table design)

The client can't undo by re-sending the old category: that would teach merchant memory the wrong thing and leave the `also_updated` rows changed. So the server records each correction.

- New table **`category_corrections`**: `user_id`, `transaction_id` (the picked row), `new_category_id`, `previous` (jsonb: for every affected row, its id, previous `category_id`, `needs_review`, `suggested_category_id`), `merchant_rule_before` (jsonb or null: the rule's previous state, or null if the correction created it), `undone_at`, timestamps.
- `PATCH /api/v1/transactions/:id` (existing, with AI3's `also_updated`) also writes a correction and returns its `correction_id`.
- **`POST /api/v1/category_corrections/:id/undo`**, in one DB transaction:
  - restores each affected row from `previous` **only if its category still equals `new_category_id`** (rows the user has changed since are left alone);
  - restores or deletes the merchant rule;
  - sets `undone_at`. A second undo is a 409; another user's correction is a 404.
- Response: the restored rows' ids and the new "to review" count.
- If you'd rather put this on the transaction (`POST /transactions/:id/undo_correction`, as discussed earlier), that's fine, as long as the stored-previous-state behaviour above is kept.

### B.3 Review list: one server summary

(Example values are illustrative; the API's real enum values and slugs win, e.g. purpose `spending`, slug `dining-out`.)

**`GET /api/v1/transactions/review_groups`** groups the user's `needs_review` rows that are **not** in a suggested transfer link, by the same normalized merchant key AI3 uses:

```json
{
  "remaining": 36,
  "groups": [
    {
      "merchant_key": "harbor bean",
      "display_name": "SQ *HARBOR BEAN",
      "count": 6,
      "total": "-41.20",
      "accounts": [
        { "id": 1, "name": "Everyday Checking", "purpose": "spending" }
      ],
      "representative_transaction_id": 123,
      "suggested_category": {
        "id": 7,
        "slug": "dining-out",
        "name": "Dining Out"
      },
      "alternatives": [{ "id": 3, "slug": "groceries", "name": "Groceries" }]
    }
  ]
}
```

- `suggested_category`: the most common `suggested_category_id` in the group, or null.
- `alternatives`: up to 2 categories, the user's most used in the same direction (money out / money in) excluding the suggestion; fall back to Other. Deterministic, no AI call.
- Order: largest `count` first, then largest absolute total. Groups with only transfer-like rows still appear (no Transfers chip).
- The client picks a chip → `PATCH /transactions/:representative_transaction_id` → AI3 updates the rest and returns `also_updated` + `correction_id`.

---

## C. C2b (review and transfer screens): client

Build to `SCREENS_ACTIVITY.md` §5–6 and the screenshots `docs/product/screens/Activity-Review.png` and `Activity-Transfers.png`, with these details:

- **Review card after a pick:** "<Category> · also updated N others" and an **Undo** link (calls B.2). The card stays in place until the screen is left, so Undo is reachable.
- **Chips:** suggestion first as "<Name>?" (Fern background, Pine border), then alternatives, then "More…" (full category list, no Transfers). If there's no suggestion, show only alternatives and "More…".
- **Activity list:** rows in review show "<Suggestion>?" in review colours, or "Needs review" when there's no suggestion; rows in a suggested transfer link show "Transfer?". The "transfers to confirm" tile appears once TR1 exists and is hidden at 0.
- **Transfers:** confirm → "Confirmed · left out of spending and income" with Undo; reject → "Got it · won't suggest this pair again" with Undo.
- **Done state:** when "to review" reaches 0, show a small celebration with the mascot (`assets/brand/mascot.svg`): "All caught up". Mascot use here is per D-020 (celebrations).
- Tests: chip rendering with and without a suggestion; undo restores the card; the Activity chip states.

**Acceptance (owner's phone, after `demo:reset`):**

1. Review shows merchant groups with "?" suggestions; picking one updates the whole group and shows "also updated N others".
2. Undo restores the group and the count, and the merchant isn't remembered any more (re-import or a new row from that merchant goes back to review).
3. Transfers lists the suggested pairs; confirm removes both rows from review and shows them as Transfers; Undo puts them back.
4. Reject keeps the rows in review; running matching again doesn't re-suggest the pair.
5. Reaching 0 to review shows "All caught up".

---

## D. CI1 and EV1 (unchanged from plan rev. 4.1)

- **CI1 (GitHub Actions CI):** one workflow per repo. Server: `bin/rails test` with a Postgres service. Client: `tsc` must not exceed the recorded baseline (48), plus `npm run test:ci`. No secrets needed; never calls Claude.
- **EV1 (categorization eval):** golden synthetic set run through the real pipeline; report accuracy overall and per category, the share sent to review, and the **transfer critical-error count** (a transfer-like row categorized as spending or income must be 0). Manual or `workflow_dispatch` only, under the daily AI cap. Save the report in `docs/evals/` with the date and model id; it's a portfolio artefact.

---

## What comes back to Claude Project

TR1's pair and review counts on demo data; any changes you made to §A–C and why; the EV1 report. Then M2 begins: Claude Project is preparing the Plan tab (C8) and Coach chat (C4) designs, and the AI specs for onboarding (ON1/ON2), plan drafting (PL1/PL2) and coach Q&A (AS1/AS2).
