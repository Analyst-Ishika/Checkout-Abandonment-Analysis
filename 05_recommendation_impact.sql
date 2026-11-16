# Recommendations, impact sizing, A/B test design
# Note: recovery rates are assumptions, not measured.

# Recommendation
# 1. Tracking check on payment.html (1,292 non-payers, 30.1%, no next page_view)
# 2. Exit survey on yourinfo.html (1,824 non-payers, 42.5%, went home)
# 3. Form error / field drop-off logging (330 non-payers, 7.69%, same page)
# 4. Proactive chat support (weakest evidence: 70.55 s vs 49.11 s, different end points)

# Impact = lost sessions × recovery rate × average order value
# AOV = total revenue / distinct orders

select ecommerce.transaction_id, count(distinct ecommerce.purchase_revenue_in_usd) `count`
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
where _table_suffix between '20201101' and '20210131'
group by 1
having `count` > 1;

select
  ecommerce.transaction_id,
  max(ecommerce.purchase_revenue_in_usd) - min(ecommerce.purchase_revenue_in_usd) diff
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
where _table_suffix between '20201101' and '20210131'
  and ecommerce.transaction_id is not null and ecommerce.transaction_id != '(not set)'
group by 1
having diff > 0
order by diff desc;

# 15 of 4,451 valid transaction_ids (0.34%) have 2 different revenue values.

with cte as(
  select ecommerce.transaction_id, max(ecommerce.purchase_revenue_in_usd) max_rev, min(ecommerce.purchase_revenue_in_usd) min_rev
  from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  where _table_suffix between '20201101' and '20210131'
    and ecommerce.transaction_id is not null and ecommerce.transaction_id != '(not set)'
    and event_name = 'purchase'
  group by 1
)
select 
  round(sum(max_rev) / count(transaction_id),2) max_aov,
  round(sum(min_rev) / count(transaction_id),2) min_aov
from cte;

# AOV (valid transaction_ids, 4,451 orders): MAX = $69.24, MIN = $69.04. Difference $0.20, negligible.
# Rule: MAX per transaction_id, revenue column = purchase_revenue_in_usd.

with inputs as(
  select 4292 as lost_sessions, 69.24 as aov
), rates as(
  select 'low' as scenario, 0.02 as recovery_rate
  union all select 'medium', 0.05
  union all select 'high', 0.10
)
select
  scenario, recovery_rate, lost_sessions, 
  round(lost_sessions * recovery_rate,2) recovered_orders, aov,
  round(recovery_rate * lost_sessions * aov,2) as extra_revenue_3_months
from rates
cross join inputs
order by recovery_rate;

# Impact (4,292 lost sessions x recovery rate x $69.24 AOV, Nov-Jan):
# Low 2%: ~$5.9K | Medium 5%: ~$14.9K | High 10%: ~$29.7K
# Recovery rates are assumptions, not measured. Needs A/B test to validate.

# A/B test design (sample size from Evan Miller calculator, not SQL)
# Test: simplified checkout header on yourinfo.html (fewer exit links).
# Because: 1,824 of 4,292 non-payers (42.5%) went home after shipping info. Cause unproven, so this is a candidate.
# Primary metric: shipping -> payment rate (baseline 61.35%)
# Win: Group B >= 64.35% (+3 points) at 95% confidence, 80% power
# Guardrail: payment -> purchase rate must not fall below 71.11%
# Split: random, both groups run at the same time
# MDE +2: 9,330 per group (18,660 total)
# MDE +3: 4,151 per group (8,302 total)  <- chosen (judgment call)
# MDE +4: 2,337 per group (4,674 total)
# Duration: ~2.2 months at ~3,700 shipping-stage sessions per month (sample data, real volume will differ). Full weeks only.
