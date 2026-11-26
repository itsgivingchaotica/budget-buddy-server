# Categorization eval (EV1): 2026-11-26

- **Run:** 2026-11-26T02:52:10Z · model `claude-haiku-5-5` · golden set of 300 synthetic rows (Demo::Generator seed 20261124, end date 2026-11-20)
- **Where the labels come from:** each row's expected category is the one the demo generator assigned when it created the row (merchant, amount and category are chosen together, before any categorization). The eval never takes a label from the pipeline's output; it only compares that output with the generator's labels. No real data is used.
- **Setup:** a separate eval user with empty merchant memory; the real pipeline (merchant memory → transfer check → keyword rules → Claude), with the daily AI cap in place.
- **Claude usage:** 1 request, 3093 input + 763 output tokens, about $0.0007 at list price.

## Headline

| Metric | Value |
|---|---|
| **Accuracy of auto-categorized rows** (categories the user never checks) | **100.0%** (257 of 257) |
| Review rate (sent to the user) | 14.3% (43 of 300) |
| **Transfer critical errors** (a transfer categorized as spending or income without review; must be 0) | **0** |
| Transfers sent to review instead (for transfer matching) | 18 of 18 |
| Correct without any user action (auto-correct / all rows) | 85.7% |

## By stage (auto-categorized rows)

| Stage | Rows | Correct | Accuracy |
|---|---|---|---|
| Merchant memory | 0 | 0 | n/a |
| Keyword rules | 250 | 250 | 100.0% |
| Claude | 7 | 7 | 100.0% |

## Rows sent to review

| | Rows |
|---|---|
| Sent to review | 43 |
| … with a suggestion ("Category?") | 25 (suggestion right: 100.0%) |
| … without a suggestion | 18 |

## Per category

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

## Limitations

- **The keyword rules and the golden merchants were written together** (AI1 and DEMO-G), so 250 of 300 rows were matched by a rule. High rule accuracy here shows the rules cover the demo data, not that they generalize to real bank exports.
- **Claude saw few rows:** it categorized 7 and suggested 25 more. That is too small a sample to estimate Claude's accuracy; a harder golden set (merchants the rules don't know, ambiguous and noisy descriptions) is needed for that.
- **Some labels are judgement calls** (e.g. "other" for marketplaces such as Amazon or Target); those rows are expected to go to review.
- Synthetic data only; one run (Claude's answers can vary between runs).

## Mistakes among auto-categorized rows

None.
