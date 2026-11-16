# Where Do Customers Drop Off in Checkout?
**Of 11,106 sessions that began checkout, 43.6% reached purchase. The biggest drop is between `add_shipping_info` and `add_payment_info`, where 4,292 sessions were lost. The product team should investigate the details page (`yourinfo.html`) first.**

![Dashboard](images/Checkout%20Abandonment%20Dashboard%20PNG.jpg)

## Business question
Where in the checkout flow do customers drop off most, and what should the product team fix?

## Data and tools
- Google Merchandise Store GA4 sample (BigQuery public dataset), Nov 1, 2020 to Jan 31, 2021
- BigQuery SQL, Power BI

## Method
1. **Session** = `user_pseudo_id` + `ga_session_id`. Counting is session-level.
2. **Funnel** = `begin_checkout` → `add_shipping_info` → `add_payment_info` → `purchase`. It is strict: a session counts at a step only if it passed all earlier steps.
3. **Why not start at `add_to_cart`:** 2,000 of 4,848 purchase sessions (41.3%) had no `add_to_cart` event, so the step is under-tracked.
4. **Cleaning:** removed back-to-back duplicate funnel events (78,070 → 57,925 rows, sessions unchanged). Full log in `cleaning_log.md`.

## Findings
| Step | Sessions | % of previous |
|---|---|---|
| begin_checkout | 11,106 | - |
| add_shipping_info | 11,104 | 99.98% |
| add_payment_info | 6,812 | 61.35% |
| purchase | 4,844 | 71.11% |

- **Month:** shipping → payment was 52.11% in Nov, 65.66% in Dec and 72.26% in Jan. The leak exists in all 3 months and is worst in November. Excluding the 3 tracking-suspect days changed Nov to 51.07%.
- **Device:** no effect (60.77% to 63.33%).
- **Country:** no clear effect (59.04% to 65.57%). Extremes are small groups.
- **Channel:** among known channels, referral 66.68% vs organic 56.79% and cpc 55.13%. cpc cells are under 200 sessions per month.
- **Where non-payers go next (n = 4,292):** Home 42.5%, no next page view 30.1%, Basket 9.25%, same page 7.69%, category/product 6.41%, sign-in 1.98%, policy/FAQ 1.49%.

## Hypotheses (not proven)
1. **Users leave checkout and restart shopping.** Home + Basket = 51.75%. *Supported, cause unknown.*
2. **Form friction.** Same-page share is 7.69%. *Weak.*
3. **Non-payers hesitate longer.** Median stay 70.55 s vs 49.11 s, but the end points differ. *Weak.*

## Recommendations (ranked)
1. Tracking check on `payment.html` (1,292 non-payers, 30.1%, have no later page view).
2. Exit survey on `yourinfo.html` (1,824 non-payers, 42.5%, went home).
3. Log form errors and field drop-off (330 non-payers, 7.69%).
4. Proactive chat support (weakest evidence).

## Impact (assumption-based, 3 months)
Impact = 4,292 lost sessions × recovery rate × $69.24 AOV (4,451 valid orders)

| Scenario | Recovery | Extra revenue |
|---|---|---|
| Low | 2% | $5,943.56 |
| Medium | 5% | $14,858.90 |
| High | 10% | $29,717.81 |

Recovery rates are my assumptions, not measured.

## A/B test design
- **Test:** simplified checkout header on `yourinfo.html` (candidate only)
- **Primary metric:** shipping → payment rate (baseline 61.35%)
- **Win:** at least +3 points (64.35%) at 95% confidence, 80% power
- **Guardrail:** payment → purchase rate must not fall below 71.11%
- **Sample:** 4,151 per group (8,302 total), random split, both groups at the same time
- **Duration:** about 2.2 months at this dataset's traffic (real volume will differ)

## Limitations
- `user_id` is NULL, so users are devices, not people.
- Session-level: a buyer who returns in a new session still counts as abandoned in the earlier session.
- 3,718 sessions (33.5%) have `(none)` or `(data deleted)` as source.
- 906 purchase events (15.9%) have no valid `transaction_id` (8.8% of revenue).
- Item data is empty on shipping events, so cart value of abandoners can't be measured.
- The data shows where users leave, not why.
- Sample dataset from a single store, holiday-heavy window.
- The 10-point spread cutoff in the segment analysis is a judgment call, not a statistical test.

## Repo structure
```
sql/
  phase_0_2_setup_validate.sql
  phase_3_funnel.sql
  phase_4_segments.sql
  phase_5_hypotheses.sql
  phase_6_recommendation_impact.sql
cleaning_log.md
images/dashboard.png
README.md
```
