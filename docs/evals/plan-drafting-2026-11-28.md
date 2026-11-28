# Plan drafting eval (PL1): 2026-11-28

**Status:** Eval report (Builder, 2026-11-28) · two runs of `bin/rails "eval:plan_drafting[10]"`, before and after D-035 (intro limit 240 characters)

Why: 2 of the first 4 sample drafts after D-034 item 5 fell back. The owner asked for every validated limit to be stated in the model request, the failed checks to be recorded as generic codes in each draft, and 10 drafts measured (target: fallback < 10%); if intro length was a cause, the intro limit goes to 240 characters (D-035, approved in advance).

- **Data:** the synthetic demo user (`demo:seed`), 6 covered months; answers: pay biweekly, side income yes, 7 bills, 2 goals (2 without a date), appetite "trim". The same answers for every draft, so differences come from the model.
- **Limits checked:** intro ≤ 200 (run A) / 240 (run B) characters, reasons ≤ 80, no digits, every category once with a real option, ≤ 3 trims and no stretch for small trims, at least one change (D-034); all stated in the request.

## Run A: intro ≤ 200 characters

- **Run:** 2026-11-28T04:55:08Z · model `claude-haiku-5-5` · real `PlanDrafter` (one call, Rails' checks, one retry, then the fallback), daily AI cap in place · 10 drafts.
- **Claude usage:** 12 requests, 20458 input + 8808 output tokens, about $0.0064 at list price.

### Headline

| | Drafts | Share |
|---|---|---|
| **Fallback** (target < 10%) | **0** | **0%** |
| Model's answer passed on the first try | 8 | 80% |
| Passed after the one retry | 2 | 20% |

**Result:** meets the target.

### Failed checks (generic codes, every try)

| Code | Tries | In drafts that fell back |
|---|---|---|
| `intro_too_long` | 2 | 0 |

### The model's drafts

- Intro length: 153–185 characters (mean 174).
- Categories changed (trim or stretch) per draft: 2 in 6, 3 in 4.

## Run B: intro ≤ 240 characters (D-035)

- **Run:** 2026-11-28T04:56:27Z · model `claude-haiku-5-5` · real `PlanDrafter` (one call, Rails' checks, one retry, then the fallback), daily AI cap in place · 10 drafts.
- **Claude usage:** 15 requests, 25677 input + 6085 output tokens, about $0.0056 at list price.

### Headline

| | Drafts | Share |
|---|---|---|
| **Fallback** (target < 10%) | **0** | **0%** |
| Model's answer passed on the first try | 5 | 50% |
| Passed after the one retry | 5 | 50% |

**Result:** meets the target.

### Failed checks (generic codes, every try)

| Code | Tries | In drafts that fell back |
|---|---|---|
| `missing_category` | 3 | 0 |
| `intro_too_long` | 2 | 0 |

### The model's drafts

- Intro length: 175–239 characters (mean 214).
- Categories changed (trim or stretch) per draft: 1 in 1, 2 in 6, 3 in 3.

## Reading the results

- **Fallback rate: 0 of 20 drafts in both runs**, well under the 10% target. Stating every limit in the request did the main work: before it, 2 of 4 sample drafts fell back.
- **Intro length was the only failed check in run A** (2 of 12 tries), so D-035 raised the limit to 240. In run B the model **used the extra room**: intros grew from a mean of 174 to 214 characters, and 2 tries still ran over. Retries went up (2 → 5 drafts needed one), partly from `missing_category` (a category left out), which run A didn't show.
- Each run is only 10 drafts, so the change in retries may be chance. Neither run fell back.

## Limitations

- One user and one set of answers ("Small trims", 2 undated goals); other appetites (keep, push) and other data aren't covered.
- 10 drafts per run is a small sample: one fallback moves the rate by 10%.
- The report counts checks, not tone; tone was reviewed by the Planner on the sample draft (D-034).
