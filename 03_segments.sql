# Month, including the with/without view for Nov 24, 25 and Jan 27
select
  format_date('%B',event_date) month, 
  countif(reached_1) reached_1,countif(reached_2) reached_2,countif(reached_3) reached_3,countif(reached_4) reached_4,
  round(countif(reached_2) * 100 / count(session_id),2) `reached_2_%`,
  round(countif(reached_2) / countif(reached_1) * 100,2) `%_of_previous_2`,
  round(countif(reached_3) * 100 / count(session_id),2) `reached_3_%`,
  round(countif(reached_3) / countif(reached_2) * 100,2) `%_of_previous_3`,
  round(countif(reached_4) * 100 / count(session_id),2) `reached_4_%`,
  round(countif(reached_4) / countif(reached_3) * 100,2) `%_of_previous_4`
from `ca-analysis4.cart_abandonement_analysis.session_funnel`
group by 1;

select
  format_date('%B',event_date) month, 
  countif(reached_1) reached_1,countif(reached_2) reached_2,countif(reached_3) reached_3,countif(reached_4) reached_4,
  round(countif(reached_2) * 100 / count(session_id),2) `reached_2_%`,
  round(countif(reached_2) / countif(reached_1) * 100,2) `%_of_previous_2`,
  round(countif(reached_3) * 100 / count(session_id),2) `reached_3_%`,
  round(countif(reached_3) / countif(reached_2) * 100,2) `%_of_previous_3`,
  round(countif(reached_4) * 100 / count(session_id),2) `reached_4_%`,
  round(countif(reached_4) / countif(reached_3) * 100,2) `%_of_previous_4`
from `ca-analysis4.cart_abandonement_analysis.session_funnel`
where event_date not in ('2020-11-24','2020-11-25','2021-01-27')
group by 1;

# I show results with and without Nov 24, Nov 25 and Jan 27, because over 10% of funnel sessions on those days lack a session_start event, which suggests a tracking issue.
# Month check: shipping → payment is the weakest step in Nov, Dec and Jan. Excluding Nov 24, Nov 25 and Jan 27 (tracking-suspect days) changes November from 52.11% to 51.07%. Finding is robust to those days.

# Device
select
  device_category, 
  countif(reached_1) reached_1,countif(reached_2) reached_2,countif(reached_3) reached_3,countif(reached_4) reached_4,
  round(countif(reached_2) * 100 / count(session_id),2) `reached_2_%`,
  round(countif(reached_2) / countif(reached_1) * 100,2) `%_of_previous_2`,
  round(countif(reached_3) * 100 / count(session_id),2) `reached_3_%`,
  round(countif(reached_3) / countif(reached_2) * 100,2) `%_of_previous_3`,
  round(countif(reached_4) * 100 / count(session_id),2) `reached_4_%`,
  round(countif(reached_4) / countif(reached_3) * 100,2) `%_of_previous_4`
from `ca-analysis4.cart_abandonement_analysis.session_funnel`
group by 1;

# Device check: shipping → payment is the weakest step on desktop (60.77%), mobile (62.07%) and tablet (63.33%). No device-specific leak. Tablet base is small (240).

# Traffic source (medium)
select
  medium, 
  countif(reached_1) reached_1,countif(reached_2) reached_2,countif(reached_3) reached_3,countif(reached_4) reached_4,
  round(countif(reached_2) * 100 / count(session_id),2) `reached_2_%`,
  round(countif(reached_2) / countif(reached_1) * 100,2) `%_of_previous_2`,
  round(countif(reached_3) * 100 / count(session_id),2) `reached_3_%`,
  round(countif(reached_3) / countif(reached_2) * 100,2) `%_of_previous_3`,
  round(countif(reached_4) * 100 / count(session_id),2) `reached_4_%`,
  round(countif(reached_4) / countif(reached_3) * 100,2) `%_of_previous_4`
from `ca-analysis4.cart_abandonement_analysis.session_funnel`
group by 1;

# Medium check: shipping → payment ranges from 55.13% (cpc) to 66.68% (referral) among known channels. Payment → purchase is flat. 3,718 sessions are (none) or (data deleted), so the channel conclusion is limited.

# Country (top countries only)
select country, count(*) `count`
from `ca-analysis4.cart_abandonement_analysis.session_funnel`
group by 1
order by 2 desc;

select
  case when country in('United States','India','Canada','United Kingdom','Spain','France') then country
    else 'Other Countries'
  end as country,
  countif(reached_1) reached_1,countif(reached_2) reached_2,countif(reached_3) reached_3,countif(reached_4) reached_4,
  round(countif(reached_2) * 100 / count(session_id),2) `reached_2_%`,
  round(countif(reached_2) / countif(reached_1) * 100,2) `%_of_previous_2`,
  round(countif(reached_3) * 100 / count(session_id),2) `reached_3_%`,
  round(countif(reached_3) / countif(reached_2) * 100,2) `%_of_previous_3`,
  round(countif(reached_4) * 100 / count(session_id),2) `reached_4_%`,
  round(countif(reached_4) / countif(reached_3) * 100,2) `%_of_previous_4`
from `ca-analysis4.cart_abandonement_analysis.session_funnel`
group by 1;

# Country check: shipping → payment is the weakest step in all 6 countries and the pooled group (59.04% to 65.57%). No country-specific leak. UK, Spain and France have small bases

# Spread = max - min of %_of_previous_3 across groups within one segment.
# I treat a spread above 10 percentage points as worth investigating.
# This 10-point cutoff is my judgment call, not a statistical test.
# Group size is not accounted for, so check session counts before trusting a spread.
with seg as(
  select
    'month' segment,format_date('%B',event_date) month,
    round(countif(reached_3) / countif(reached_2) * 100,2) pct_prev_3
  from `ca-analysis4.cart_abandonement_analysis.session_funnel`
  group by 1,2
  union all
  select
    'device',device_category,
    round(countif(reached_3) / countif(reached_2) * 100,2) 
  from `ca-analysis4.cart_abandonement_analysis.session_funnel`
  group by 1,2
  union all
  select
    'medium',medium,
    round(countif(reached_3) / countif(reached_2) * 100,2) 
  from `ca-analysis4.cart_abandonement_analysis.session_funnel`
  group by 1,2
  union all
  select
    'medium_without_unknown', medium,
    round(countif(reached_3) / countif(reached_2) * 100,2) 
  from `ca-analysis4.cart_abandonement_analysis.session_funnel`
  where medium not in ('<Other>','(none)','(data deleted)')
  group by 1,2
  union all
  select
    'country',
    case when country in ('United States','India','Canada','United Kingdom','Spain','France') then country
      else 'Other Countries'
    end,
    round(countif(reached_3) / countif(reached_2) * 100,2)
  from `ca-analysis4.cart_abandonement_analysis.session_funnel`
  group by 1,2
)
select 
  segment, min(pct_prev_3) min_pct, max(pct_prev_3) max_pct, round(max(pct_prev_3) - min(pct_prev_3),2) spread
from seg
group by 1
order by 4 desc;

# Result: medium 28.2 (inflated by unknown groups), month 20.15, medium_without_unknown 11.55, country 6.53, device 2.56. Above 10: month and medium (known channels only).
  
select
  format_date('%B',event_date) month,
  medium,
  countif(reached_1) sessions,
  round(countif(reached_3) * 100 / count(session_id),2) `reached_3_%`,
  round(countif(reached_3) / countif(reached_2) * 100,2) `%_of_previous_3`,
  round(countif(reached_4) * 100 / count(session_id),2) `reached_4_%`,
  round(countif(reached_4) / countif(reached_3) * 100,2) `%_of_previous_4`
from `ca-analysis4.cart_abandonement_analysis.session_funnel`
group by 1,2;

# Referral beats organic at shipping → payment in all 3 months (Nov 59.76 vs 44.36, Dec 70.28 vs 63.30, Jan 73.81 vs 70.99). Gap narrows. cpc cells are under 200 sessions (175, 147, 69), so cpc isn’t read by month.