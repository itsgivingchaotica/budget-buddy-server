Screen spec — Activity tab (C2 accounts and import screens, C2b review and transfer screens)
Status: DRAFT for product-owner review (2026-11-24).
Visual source: design canvas, page "Activity" (https://claude.ai/artifact/DkfvXfySAgRetsnG4b9MFf). Claude Code can't open the canvas, so this doc is the build reference; the canvas shows the look.
Applies: D-019 (tabs, first run), D-020 (brand), D-021 (Left to spend), AI3 (learn from corrections, also_updated), TR1 (transfer matching).

Shared rules
Brand (D-020): background Birch
#F6F1E7; cards white, radius 18; primary buttons Pine
#2F5D46 with white text; secondary buttons white with Pine border; text Bark
#3A2A1E, secondary text
#5B4A3C; "needs review" chips
#F6E7DA background with Chestnut
#8E4A1F text; confirmed/positive chips Fern
#DCE6D2 with Pine text. Headings Bricolage Grotesque 700; body Inter.
Phone size: designed at 390 × 844. Content scrolls; the tab bar stays fixed.
Tab bar: Home, Plan, Activity, Coach. On Activity screens the Activity tab is active.
Money: amounts arrive from the API as strings ("-64.18"). Display money out as −$64.18 in Bark, money in as +$120.00 in Pine. One shared formatting helper.
Accessibility: real buttons and links; touch targets ≥ 44 px; selected chips expose aria-pressed; colour never carries meaning alone (review state always has the word "review" or a "?" suggestion).
Errors: every network error shows a short message and a retry, never a silent failure.

1. Activity (tab root) — C2
   Purpose: see recent transactions and what needs attention.

Element Behaviour API
Title "Activity" + Import button Opens Import (§4) —
"3 accounts · data through <date>" + Accounts link Earliest data_through across active accounts; link opens Accounts (§2) GET /accounts
"N to review" card Count of needs_review transactions; opens Review (§5). Hidden when 0 GET /transactions?needs_review=true (count)
"N transfers to confirm" card Count of suggested transfer links; opens Transfers (§6). Hidden when 0, and hidden entirely until TR1 exists GET /transfer_links?status=suggested
Account filter chips All + one per active account; filters the list GET /transactions?account_id=
Transaction list Grouped by date (newest first); row = description, category chip (or suggestion with "?" when needs_review), account name, amount; paginated on scroll GET /transactions
Empty state: no accounts → "Add your first account" button to §3.

2. Accounts — C2
   Element Behaviour API
   Back to Activity — —
   Account cards Name; kind · purpose; "N transactions · through <date>"; freshness chip: "Up to date" (Fern) if data_through within 7 days, else "N days old" (review colours) GET /accounts
   Import CSV per card Opens Import with that account preselected —
   Add account Opens §3 —
   Footer "N archived accounts · history kept"; link to the CSV template template: public/csv-templates/generic.csv
3. Add account — C2
   Element Behaviour API
   Name field (with visible label) Required; unique per user ignoring case (show the server's 422 message inline) POST /accounts
   Type chips Checking, Savings, Credit card, Payment app, Cash, Other → kind
   "What do you mostly use it for?" chips Everyday spending, Paying bills, Saving for goals, Side-job income, Other → purpose. Helper text: the coach uses this (e.g. to recognise side-job income)
   Save and import CSV (primary) Creates the account, then opens Import for it
   Save without importing Creates the account, returns to Accounts
4. Import and result — C2
   Before upload: account (with "Change"), file picker (expo-document-picker, CSV only), template link.

After upload — result card:

Figure Source in the import response
"N transactions added" + date range + "file not kept" inserted count, data_from–data_through
Categorized automatically rows not needing review
To review rows with needs_review (review colours)
Duplicates skipped duplicate count
Rows couldn't be read row error count; "Show the N rows" expands friendly messages per error code (e.g. bad_date → "the date isn't in a format we read"), with line numbers. Never row text
Actions: "Review N now" (primary, to §5; hidden when 0), "Done for now".
Whole-file errors (422): show the reason in plain words (e.g. missing columns lists the required ones) with "Choose another file".
AI cap reached (S4-min): import still succeeds; show "Some transactions will be categorized later" if the server says so.

5. Review — C2b
   Purpose: clear uncertain categories fast, one decision per merchant.

Element Behaviour API
Title "To review · N" Live count GET /transactions?needs_review=true
Merchant cards Grouped by merchant: description, "N transactions · account (· purpose when relevant)", total (grouping client-side or a server summary)
Chips First chip = suggested category with "?" (Fern, Pine border); 1–2 alternatives; "More…" opens the full category list GET /categories
On pick PATCH one transaction of that merchant; card collapses to "<Category> · also updated N others" using also_updated; count drops; Undo sends the previous category back PATCH /transactions/:id
Transfers are never offered as a category here (only §6 sets them).

6. Transfers — C2b (needs TR1)
   Element Behaviour API
   Title "Transfers · N" + one-line explanation — GET /transfer_links?status=suggested
   Pair cards Amount; "Same day" / "N days apart"; out-of account, date, description → into account, date, description
   Not a transfer / Confirm Confirm: "Confirmed · left out of spending and income". Reject: "Got it · won't suggest this pair again". Both with Undo POST /transfer_links/:id/confirm, /reject, DELETE /transfer_links/:id
   Acceptance (manual, on the phone, with demo data)
   Activity shows the three demo accounts' transactions, newest first, with the account filter working.
   Accounts shows each account's freshness correctly.
   Adding an account with a duplicate name shows the server's message inline.
   Importing the overlapping demo export reports duplicates and adds nothing new; importing the bad-rows file shows 3 readable error messages.
   In Review, picking a category for a merchant clears all its waiting rows and shows "also updated N others"; Undo restores them.
   In Transfers (after TR1), confirming a pair removes it from spending; rejecting it means it isn't suggested again.
