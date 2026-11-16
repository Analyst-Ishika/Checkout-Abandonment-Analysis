# Min and Max date 
select min(event_date), max(event_date) from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`;

# One day data 
select * from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20201101` limit 10;

# Session id = user_pseudo_id + ga_session_id
select user_pseudo_id,
  (select value.int_value from unnest(event_params) where key = 'ga_session_id') ga_session_id, event_name,
  (select value.string_value from unnest(event_params) where key = 'page_location') page_location,
  device.category, geo.country
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20201101`
order by user_pseudo_id, ga_session_id;

# Distinct sessions in a day
select count(distinct(concat(user_pseudo_id, ' ',
  (select value.int_value from unnest(event_params) where key = 'ga_session_id'))))
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20201101`;

# Checking null ga_session_id
select * from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
where (_table_suffix between '20201101' and '20210131')
  and (select value.int_value from unnest(event_params) where key = 'ga_session_id') is null;

select
  countif((select value.int_value from unnest(event_params) where key = 'ga_session_id') is not null) has_session,
  countif((select value.int_value from unnest(event_params) where key = 'ga_session_id') is null) null_session,
  countif(user_pseudo_id is null) null_user_id,
  count(*) `rows`
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
where _table_suffix between '20201101' and '20210131';

# Create new clean table
create or replace table `ca-analysis4.cart_abandonement_analysis.events` as
select
  user_pseudo_id,
  (select value.int_value from unnest(event_params) where key = 'ga_session_id') as ga_session_id,
  concat(user_pseudo_id,'-',
  cast((select value.int_value from unnest(event_params) where key = 'ga_session_id') as string)) session_id,
  event_date,event_timestamp, event_name,
  device.category as device_category,
  geo.country as country,
  traffic_source.medium as medium
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
where _TABLE_SUFFIX between '20201101' and '20210131';

# Distinct sessions and total rows
select count(distinct session_id), count(*) `rows`
from `ca-analysis4.cart_abandonement_analysis.events`;

# Distinct event names
select distinct event_name from `ca-analysis4.cart_abandonement_analysis.events`;

# Funnel [add_to_cart → begin_checkout → add_shipping_info → add_payment_info → purchase]

# Checking if funnel is broken 
select
  session_id,
  sum(case when event_name = 'add_to_cart' then 1 else 0 end) add_to_cart,
  sum(case when event_name = 'purchase' then 1 else 0 end) purchase
from `ca-analysis4.cart_abandonement_analysis.events`
group by 1
having (add_to_cart = 0) and (purchase > 0);
# there is data where purchase has occured without adding to cart

# Finding purchases without adding to cart
with ctc as(
  select
    session_id,
    sum(case when event_name = 'add_to_cart' then 1 else 0 end) add_to_cart,
    sum(case when event_name = 'purchase' then 1 else 0 end) purchase
  from `ca-analysis4.cart_abandonement_analysis.events`
  group by 1
)
select
  countif(purchase > 0) purchase,
  countif((purchase > 0) and (add_to_cart = 0)) purchase_without_cart,
  countif((purchase > 0) and (add_to_cart > 0)) purchase_with_cart,
  round((100 * (countif((purchase > 0) and (add_to_cart = 0)))) / (countif(purchase > 0)),1) pct_without_cart
from ctc;

# Checking whether 2000 rows where purchase has occured without adding to cart have other funnels occured or not
with ctc as(
  select session_id,
    max(event_name = 'add_to_cart') has_cart,
    max(event_name = 'begin_checkout') has_checkout,
    max(event_name = 'add_shipping_info') has_ship,
    max(event_name = 'add_payment_info') has_pay,
    max(event_name = 'purchase') has_purchase
  from `ca-analysis4.cart_abandonement_analysis.events`
  group by 1
)
select
  count(*) `rows`,
  countif(has_checkout) with_checkout,
  countif(has_ship) with_shipping,
  countif(has_pay) with_pay
from ctc
where has_purchase and not has_cart;
# there are 4 sessions where shipping is false and 3 sessions where checkout and pay is false

# Checking those sessions
with ctc as(
  select session_id,
    max(event_name = 'add_to_cart') has_cart,
    max(event_name = 'begin_checkout') has_checkout,
    max(event_name = 'add_shipping_info') has_ship,
    max(event_name = 'add_payment_info') has_pay,
    max(event_name = 'purchase') has_purchase
  from `ca-analysis4.cart_abandonement_analysis.events`
  group by 1
)
select * from ctc
where (not has_checkout or not has_ship or not has_pay)
  and (has_purchase and not has_cart);

# Percentage of events occured in a session before purchase
with ctc as(
  select session_id,
    max(event_name = 'add_to_cart') has_cart,
    max(event_name = 'begin_checkout') has_checkout,
    max(event_name = 'add_shipping_info') has_ship,
    max(event_name = 'add_payment_info') has_pay,
    max(event_name = 'purchase') has_purchase
  from `ca-analysis4.cart_abandonement_analysis.events`
  group by 1
)
select
  countif(has_cart) / count(*) * 100 pct_cart,
  countif(has_checkout) / count(*) * 100 pct_checked,
  countif(has_ship) / count(*) * 100 pct_ship,
  countif(has_pay) / count(*) * 100 pct_pay  
from ctc
where has_purchase;

with ctc as(
  select session_id,
    max(event_name = 'add_to_cart') has_cart,
    max(event_name = 'begin_checkout') has_checkout,
    max(event_name = 'add_shipping_info') has_ship,
    max(event_name = 'add_payment_info') has_pay,
    max(event_name = 'purchase') has_purchase
  from `ca-analysis4.cart_abandonement_analysis.events`
  group by 1
)
select
  *
from ctc
where has_purchase
  and (not has_checkout or not has_ship or not has_pay);

# Checking same session, same repeated events because of reload
with ctc as(
  select session_id, count(*) count_checkout
  from  `ca-analysis4.cart_abandonement_analysis.events`
  where event_name = 'begin_checkout'
  group by 1
)
select 
  case count_checkout
    when 1 then '1'
    when 2 then '2'
    when 3 then '3'
    else '4+'
  end as bucket, 
  count(session_id) sessions
from ctc 
group by 1
order by 1;

select * from `ca-analysis4.cart_abandonement_analysis.events`
where session_id in('29640692.9507522627-9961229291', '90394943.1767603223-8518266382', '19173235.3605594670-307535357')
  and event_name in ('begin_checkout','add_shipping_info','add_payment_info','purchase')
order by event_date, event_timestamp;

# Create a new funnel table
create or replace table `ca-analysis4.cart_abandonement_analysis.funnel_events` as
select *,
  case event_name
    when 'begin_checkout' then 1
    when 'add_shipping_info' then 2
    when 'add_payment_info' then 3
    when 'purchase' then 4
  end as event_step
from `ca-analysis4.cart_abandonement_analysis.events`
where event_name in('begin_checkout','add_shipping_info','add_payment_info','purchase');
# Note: add_to_cart excluded, missing in 41.3% of purchase sessions

# Create a new table removing duplicates
create or replace table `ca-analysis4.cart_abandonement_analysis.funnel_dedup`  as(
  with ctc as(
    select
      *,
      lag(event_name) over(partition by session_id order by event_timestamp, event_step) prev_event
    from `ca-analysis4.cart_abandonement_analysis.funnel_events`
  )
  select * from ctc   
  where (event_name != prev_event) or (prev_event is null)
);

select count(distinct session_id) sessions from `ca-analysis4.cart_abandonement_analysis.funnel_events`
union all
select count(distinct session_id) sessions from `ca-analysis4.cart_abandonement_analysis.funnel_dedup`;

# Creating buckets for purchase row 
with ctc as(
  select
    session_id, count(*) purchase_count
  from `ca-analysis4.cart_abandonement_analysis.funnel_dedup`
  where event_name = 'purchase'
  group by 1
  order by 2 desc
)
select
  case purchase_count
    when 1 then '1'
    when 2 then '2'
    when 3 then '3'
    else '4+'
  end as bucket,
  count(*) `count`
from ctc
group by 1;

# Checking transaction id of purchases
select
  count(*) `rows` , count(ecommerce.transaction_id) total_transaction_id, countif(ecommerce.transaction_id is null) null_id, countif(ecommerce.transaction_id = '(not set)') not_set_id
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
where (_table_suffix between '20201101' and '20210131')
  and event_name = 'purchase';

# Rows where transaction_id is not set or null and there revenue_in_usd
select 
  event_date,event_timestamp,user_pseudo_id,ecommerce.transaction_id,
  ecommerce.purchase_revenue_in_usd
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
where (_table_suffix between '20201101' and '20210131')
  and event_name = 'purchase'
  and ((ecommerce.transaction_id is null) or (ecommerce.transaction_id = '(not set)'));

# Percentage of null and not set revenue
select
  sum(
    case 
      when ecommerce.transaction_id is null then ecommerce.purchase_revenue_in_usd 
      when ecommerce.transaction_id = '(not set)' then ecommerce.purchase_revenue_in_usd
      else 0
    end) /
    sum(ecommerce.purchase_revenue_in_usd) * 100 pct_no_transaction_id
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
where (_table_suffix between '20201101' and '20210131')
  and event_name = 'purchase';

# Daily Sanity check
with daily as(
  select parse_date('%Y%m%d', event_date) date, count(distinct session_id) sessions
  from `ca-analysis4.cart_abandonement_analysis.events`
  group by 1
),
median as(
  select approx_quantiles(sessions, 2)[offset(1)] median_session
  from daily
),cte as(
  select d.date, d.sessions, m.median_session,
    round(d.sessions / m.median_session, 2) ratio_to_median,
    case 
      when (d.sessions < m.median_session * 0.5) or (d.sessions > 2 * m.median_session) then 'flag'
      else 'ok'
    end as flag
  from daily d cross join median m
)
select * from cte;

# Checkout rate = checkout sessions ÷ total sessions.
with cte as(
  select
    parse_date('%Y%m%d',event_date) date,
    round(count(distinct if(event_name = 'begin_checkout', session_id, null)) * 100 / count(distinct session_id),2) checkout_rate
  from `ca-analysis4.cart_abandonement_analysis.events`
  group by 1
)
select * from cte
where date in ('2020-12-08','2020-12-09','2020-12-10');

# Baseline checkout rate excluding Dec 8-10 (total checkout sessions / total sessions)
select
  round(count(distinct if(event_name = 'begin_checkout', session_id, null)) * 100
        / count(distinct session_id), 2) as baseline_checkout_rate_pct
from `ca-analysis4.cart_abandonement_analysis.events`
where event_date not in ('20201208','20201209','20201210');

# Boundary gap where session_start is missing
select distinct session_id from `ca-analysis4.cart_abandonement_analysis.events`
where session_id not in (select session_id from `ca-analysis4.cart_abandonement_analysis.events`
  where event_name = 'session_start');

# Missing session_start ids in funnel dedup
select count(distinct session_id)
from `ca-analysis4.cart_abandonement_analysis.funnel_dedup`
where session_id in (
  select distinct session_id from `ca-analysis4.cart_abandonement_analysis.events`
  where session_id not in (select session_id from `ca-analysis4.cart_abandonement_analysis.events`
    where event_name = 'session_start'
));

# Dates and without session_start percentage 

with without_session_start as(
  select event_date, count(distinct session_id) withut_session_start
  from `ca-analysis4.cart_abandonement_analysis.funnel_dedup`
  where session_id in (
    select distinct session_id from `ca-analysis4.cart_abandonement_analysis.events`
    where session_id not in (select session_id from `ca-analysis4.cart_abandonement_analysis.events`
      where event_name = 'session_start'
  ))
  group by 1
), total_sessions as(
  select event_date, count(distinct session_id) total_sessions
  from `ca-analysis4.cart_abandonement_analysis.funnel_dedup` 
  group by 1
)
select s.event_date,s.withut_session_start,t.total_sessions,
  round((s.withut_session_start * 100) / t.total_sessions,2) pct_share
from without_session_start s 
left join total_sessions t
  on s.event_date = t.event_date