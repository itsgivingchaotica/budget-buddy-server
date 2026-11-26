# Categorization eval (EV1): 2026-11-26

- **Run:** 2026-11-26T03:07:54Z · model `claude-haiku-5-5` · real pipeline (merchant memory → transfer check → keyword rules → Claude), daily AI cap in place; a separate eval user whose merchant memory is emptied before each run.
- **Where the labels come from:** never from the pipeline's output. **Easy set:** each row's category was assigned by the demo generator when it created the row (merchant, amount and category chosen together). **Hard set:** Claude Code (before the first hard-set run) wrote each row with its label on 2026-11-26 (`lib/evals/golden_hard.yml`); labels are the author's judgement, and rows marked ambiguous have a defensible label where another is possible. The eval only compares the pipeline's output with these labels. Synthetic data only.
- **Keyword rules:** frozen since the hard set was written (fingerprint `9efd9329adcaf092` matches).
- **Claude usage (all runs):** 5 requests, 15829 input + 5077 output tokens, about $0.0041 at list price.

## Headline

| | Easy set (demo generator) | Hard set | Hard set, Claude only |
|---|---|---|---|
| Rows | 300 | 80 | 80 |
| **Accuracy of auto-categorized rows** (categories the user never checks) | **100.0%** (257/257) | **96.8%** (60/62) | **96.7%** (58/60) |
| Review rate (sent to the user) | 14.3% (43) | 22.5% (18) | 25.0% (20) |
| Suggestion right, when the row went to review with one | 100.0% (25/25) | 64.3% (9/14) | 68.8% (11/16) |
| **Transfer critical errors** (must be 0) | **0** of 18 | **0** of 6 | **0** of 6 |
| Correct with no user action (auto-correct / all rows) | 85.7% | 75.0% | 72.5% |
| Merchant memory: rows (accuracy) | 0 (n/a) | 0 (n/a) | 0 (n/a) |
| Keyword rules: rows (accuracy) | 250 (100.0%) | 20 (95.0%) | 0 (n/a) |
| Claude: rows (accuracy) | 7 (100.0%) | 42 (97.6%) | 60 (96.7%) |
| Claude usage | 1 request, 3093+763 tokens | 2 requests, 5871+1419 tokens | 2 requests, 6865+2895 tokens |

## Easy set (demo generator)

300 rows from the demo generator; full pipeline.

| Stage | Rows | Correct | Accuracy |
|---|---|---|---|
| Merchant memory | 0 | 0 | n/a |
| Keyword rules | 250 | 250 | 100.0% |
| Claude | 7 | 7 | 100.0% |
| Sent to review | 43 | with a suggestion: 25 (right: 25) | without: 18 |

**Per category**

| True category | Rows | Auto-categorized | Auto correct | Sent to review |
|---|---|---|---|---|
| clothing | 19 | 19 | 19 (100.0%) | 0 |
| debt-payments | 18 | 18 | 18 (100.0%) | 0 |
| dining-out | 18 | 13 | 13 (100.0%) | 5 |
| education | 14 | 14 | 14 (100.0%) | 0 |
| entertainment | 18 | 18 | 18 (100.0%) | 0 |
| gifts | 5 | 5 | 5 (100.0%) | 0 |
| groceries | 18 | 18 | 18 (100.0%) | 0 |
| healthcare | 18 | 18 | 18 (100.0%) | 0 |
| home-improvement | 19 | 19 | 19 (100.0%) | 0 |
| income | 18 | 16 | 16 (100.0%) | 2 |
| insurance | 5 | 5 | 5 (100.0%) | 0 |
| other | 18 | 0 | 0 (n/a) | 18 |
| personal-care | 18 | 18 | 18 (100.0%) | 0 |
| rent | 18 | 18 | 18 (100.0%) | 0 |
| subscriptions | 19 | 19 | 19 (100.0%) | 0 |
| transfers | 18 | 0 | 0 (n/a) | 18 |
| transportation | 17 | 17 | 17 (100.0%) | 0 |
| travel | 6 | 6 | 6 (100.0%) | 0 |
| utilities | 16 | 16 | 16 (100.0%) | 0 |

**Mistakes among auto-categorized rows**

None.

## Hard set

Hand-written rows (`lib/evals/golden_hard.yml`); full pipeline.

| Stage | Rows | Correct | Accuracy |
|---|---|---|---|
| Merchant memory | 0 | 0 | n/a |
| Keyword rules | 20 | 19 | 95.0% |
| Claude | 42 | 41 | 97.6% |
| Sent to review | 18 | with a suggestion: 14 (right: 9) | without: 4 |

**By row kind**

| Kind | Rows | Auto-categorized | Auto correct | Sent to review |
|---|---|---|---|---|
| ambiguous | 19 | 11 | 9 (81.8%) | 8 |
| messy | 14 | 14 | 14 (100.0%) | 0 |
| p2p | 8 | 5 | 5 (100.0%) | 3 |
| refund | 7 | 6 | 6 (100.0%) | 1 |
| transfer | 6 | 0 | 0 (n/a) | 6 |
| unknown_merchant | 26 | 26 | 26 (100.0%) | 0 |

**Per category**

| True category | Rows | Auto-categorized | Auto correct | Sent to review |
|---|---|---|---|---|
| clothing | 3 | 3 | 3 (100.0%) | 0 |
| debt-payments | 3 | 2 | 2 (100.0%) | 1 |
| dining-out | 8 | 7 | 7 (100.0%) | 1 |
| education | 2 | 2 | 2 (100.0%) | 0 |
| entertainment | 3 | 2 | 2 (100.0%) | 1 |
| gifts | 2 | 2 | 2 (100.0%) | 0 |
| groceries | 7 | 6 | 6 (100.0%) | 1 |
| healthcare | 6 | 6 | 6 (100.0%) | 0 |
| home-improvement | 4 | 4 | 4 (100.0%) | 0 |
| income | 6 | 4 | 4 (100.0%) | 2 |
| insurance | 1 | 1 | 1 (100.0%) | 0 |
| other | 9 | 3 | 1 (33.3%) | 6 |
| personal-care | 2 | 2 | 2 (100.0%) | 0 |
| rent | 2 | 2 | 2 (100.0%) | 0 |
| subscriptions | 5 | 5 | 5 (100.0%) | 0 |
| transfers | 6 | 0 | 0 (n/a) | 6 |
| transportation | 6 | 6 | 6 (100.0%) | 0 |
| travel | 3 | 3 | 3 (100.0%) | 0 |
| utilities | 2 | 2 | 2 (100.0%) | 0 |

**Mistakes among auto-categorized rows**

| Description | True | Categorized as | Stage | Kind |
|---|---|---|---|---|
| NORTHSIDE COIN LAUNDRY | other | utilities | Claude | ambiguous |
| WILLOW CREEK VET CLINIC | other | healthcare | Keyword rules | ambiguous |

## Hard set, Claude only

The same hand-written rows with the keyword rules switched off.

| Stage | Rows | Correct | Accuracy |
|---|---|---|---|
| Merchant memory | 0 | 0 | n/a |
| Keyword rules | 0 | 0 | n/a |
| Claude | 60 | 58 | 96.7% |
| Sent to review | 20 | with a suggestion: 16 (right: 11) | without: 4 |

**By row kind**

| Kind | Rows | Auto-categorized | Auto correct | Sent to review |
|---|---|---|---|---|
| ambiguous | 19 | 9 | 9 (100.0%) | 10 |
| messy | 14 | 14 | 14 (100.0%) | 0 |
| p2p | 8 | 5 | 5 (100.0%) | 3 |
| refund | 7 | 6 | 5 (83.3%) | 1 |
| transfer | 6 | 0 | 0 (n/a) | 6 |
| unknown_merchant | 26 | 26 | 25 (96.2%) | 0 |

**Per category**

| True category | Rows | Auto-categorized | Auto correct | Sent to review |
|---|---|---|---|---|
| clothing | 3 | 3 | 3 (100.0%) | 0 |
| debt-payments | 3 | 2 | 2 (100.0%) | 1 |
| dining-out | 8 | 7 | 7 (100.0%) | 1 |
| education | 2 | 2 | 2 (100.0%) | 0 |
| entertainment | 3 | 2 | 2 (100.0%) | 1 |
| gifts | 2 | 2 | 2 (100.0%) | 0 |
| groceries | 7 | 5 | 5 (100.0%) | 2 |
| healthcare | 6 | 6 | 5 (83.3%) | 0 |
| home-improvement | 4 | 3 | 3 (100.0%) | 1 |
| income | 6 | 4 | 4 (100.0%) | 2 |
| insurance | 1 | 1 | 1 (100.0%) | 0 |
| other | 9 | 3 | 3 (100.0%) | 6 |
| personal-care | 2 | 2 | 1 (50.0%) | 0 |
| rent | 2 | 2 | 2 (100.0%) | 0 |
| subscriptions | 5 | 5 | 5 (100.0%) | 0 |
| transfers | 6 | 0 | 0 (n/a) | 6 |
| transportation | 6 | 6 | 6 (100.0%) | 0 |
| travel | 3 | 3 | 3 (100.0%) | 0 |
| utilities | 2 | 2 | 2 (100.0%) | 0 |

**Mistakes among auto-categorized rows**

| Description | True | Categorized as | Stage | Kind |
|---|---|---|---|---|
| SUMMIT CLIMBING GYM | personal-care | entertainment | Claude | unknown_merchant |
| JUNIPER DENTAL STUDIO INS REIMB | healthcare | insurance | Claude | refund |

## Limitations

- **Easy set:** the keyword rules and the demo merchants were written together (AI1 and DEMO-G), so 250 of 300 rows hit a rule. It measures rule coverage of the demo data, not generalization.
- **Hard set:** 80 rows written by the same author as the rules (deliberately using merchants and phrasings the rules don't know), labelled by judgement; ambiguous rows have more than one defensible answer. Small sample: treat percentages as indicative.
- **Claude-only run:** keyword rules off; merchant memory empty; the transfer check stays on, because it only sends rows to review (it never categorizes), so the critical-error count stays comparable.
- One run each; Claude's answers can vary between runs. Synthetic data only.
- The keyword rules were not changed after the hard set was written.
