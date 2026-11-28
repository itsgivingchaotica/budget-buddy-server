# Plan drafting eval (PL1): 2026-11-28

**Status:** Eval report (Builder, 2026-11-28) · three runs of `bin/rails "eval:plan_drafting[10]"`: before D-035 (intro limit 240 characters), after it, and with an intro target and the required categories listed

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

## Run C: intro ≤ 240, aim for about 180; required categories listed

The request also says to aim for about 180 characters (owner, 2026-11-28; the hard limit stays 240) and lists every category the answer must contain, and how many.

- **Run:** 2026-11-28T05:07:43Z · model `claude-haiku-5-5` · real `PlanDrafter` (one call, Rails' checks, one retry, then the fallback), daily AI cap in place · 10 drafts.
- **Claude usage:** 10 requests, 17890 input + 8273 output tokens, about $0.0059 at list price.

### Headline

| | Drafts | Share |
|---|---|---|
| **Fallback** (target < 10%) | **0** | **0%** |
| Model's answer passed on the first try | 10 | 100% |
| Passed after the one retry | 0 | 0% |

**Result:** meets the target.

### Failed checks (generic codes, every try)

None: every try passed.

### The model's drafts

- Intro length: 158–229 characters (mean 196).
- Categories changed (trim or stretch) per draft: 2 in 7, 3 in 3.

## Reading the results

| | Run A (≤ 200) | Run B (≤ 240) | Run C (≤ 240, aim 180, categories listed) |
|---|---|---|---|
| **Fallback** (target < 10%) | **0 / 10** | **0 / 10** | **0 / 10** |
| **Passed on the first try** | 8 / 10 | 5 / 10 | **10 / 10** |
| Failed checks | `intro_too_long` 2 | `missing_category` 3, `intro_too_long` 2 | none |
| Intro length (mean) | 174 | 214 | 196 |

- **Fallback rate: 0 of 30 drafts**, well under the 10% target. Stating every limit in the request did the main work: before it, 2 of 4 sample drafts fell back.
- **D-035 alone (run B)** let the model write longer intros (mean 174 → 214) without removing `intro_too_long`, and retries went up. **Run C** (aim for about 180, hard limit 240, and the required categories listed by name and count) passed every draft on the first try: no `intro_too_long`, no `missing_category`.
- Each run is only 10 drafts, so the differences between runs may partly be chance; none of the 30 fell back.

## Limitations

- One user and one set of answers ("Small trims", 2 undated goals); other appetites (keep, push) and other data aren't covered.
- 10 drafts per run is a small sample: one fallback moves the rate by 10%.
- The report counts checks, not tone; tone was reviewed by the Planner on the sample draft (D-034).
