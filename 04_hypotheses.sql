-- Phase 5: Why do users leave between shipping and payment?
-- Note: results show WHERE users go, not WHY. Findings are hypotheses.

# Create table for next event after adding shipping info
create or replace table ca-analysis4.cart_abandonement_analysis.shipping_next_event as(
  with cte as(
    select
      session_id, event_date, event_timestamp, event_name,
      lead(event_name) over(partition by session_id order by event_timestamp) next_event,
      lead(event_timestamp) over(partition by session_id order by event_timestamp) next_timestamp
    from  `ca-analysis4.cart_abandonement_analysis.events`),
    rnk as(
    select *,
      row_number() over(partition by session_id order by event_timestamp) rn
    from cte where event_name = 'add_shipping_info')
    select 
      rnk.session_id,rnk.event_date,((rnk.next_timestamp - rnk.event_timestamp) / 1000000) seconds_to_next,rnk.event_name,rnk.next_event,
      case when s.reached_3 then 'payers'
        else 'non-payers'
      end as reached_payment from rnk
    join `ca-analysis4.cart_abandonement_analysis.session_funnel` as s
      on rnk.session_id = s.session_id
    where rn = 1
);

select count(*), count(distinct session_id), countif(reached_payment = 'payers'), max(seconds_to_next) from ca-analysis4.cart_abandonement_analysis.shipping_next_event;

# payers vs no-payers next_event
with cte as(
select 
  next_event,
  sum(case when reached_payment = 'payers' then 1 else 0 end) payers,
  sum(case when reached_payment = 'non-payers' then 1 else 0 end) non_payers
from ca-analysis4.cart_abandonement_analysis.shipping_next_event
group by 1)
select next_event,
  round(payers / (select sum(payers) from cte) * 100,2) payers_pct,
  round(non_payers / (select sum(non_payers) from cte) * 100,2)  non_payers_pct
from cte
order by 3 desc;

# payers and non_payers median
select 
  reached_payment,approx_quantiles(seconds_to_next,2)[offset(1)] median
from `ca-analysis4.cart_abandonement_analysis.shipping_next_event`
group by 1;

# medians are about 0.0004 seconds for non-payers and 0.0002 for payers, which means the next event fires in the same instant as shipping. That is not user behavior.

# create table for max_timestamp instead of next_event's timestamp 
create or replace table `ca-analysis4.cart_abandonement_analysis.shipping_stay_base` as(
  with cte as(
    select
      session_id, event_date, event_timestamp, event_name,
      max(event_timestamp) over(partition by session_id) max_timestamp, 
    from `ca-analysis4.cart_abandonement_analysis.events`
  ), rnk as(
    select *,
      row_number() over(partition by session_id order by event_timestamp) rn
    from cte
    where event_name = 'add_shipping_info'
  ), payers as(
    select session_id, min(event_timestamp) max_timestamp_payers from `ca-analysis4.cart_abandonement_analysis.events`
    where event_name = 'add_payment_info' group by 1
  )
  select
    rnk.session_id,rnk.event_date,rnk.event_timestamp,rnk.event_name,rnk.max_timestamp, payers.max_timestamp_payers,
    case when s.reached_3 then 'payers'
      else 'non-payers'
    end as reached_payment
  from rnk
  join `ca-analysis4.cart_abandonement_analysis.session_funnel` as s
      on rnk.session_id = s.session_id
  left join payers on rnk.session_id = payers.session_id
  where rn = 1
);

select count(*), count(distinct session_id), countif(reached_payment = 'payers') from `ca-analysis4.cart_abandonement_analysis.shipping_stay_base`;

# median for payers and non-payers
with cte as(
  select
    session_id, reached_payment,
    case when reached_payment = 'non-payers' then (max_timestamp - event_timestamp) / 1000000
      when reached_payment = 'payers' then (max_timestamp_payers - event_timestamp) / 1000000
    end as stay_seconds
  from `ca-analysis4.cart_abandonement_analysis.shipping_stay_base`
) 
select
  reached_payment, count(*) sessions,
  approx_quantiles(stay_seconds,2)[offset(1)] median
from cte
group by 1;
# Median stay after shipping: 70.55 s non-payers vs 49.11 s payers. Different end points, so weak support for hesitation.

# items and prices of abandoned sessions.
# checking null 
select
  event_name,
  array_length(`items`) n_items,
  count(*) events
from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
where _table_suffix between '20201101' and '20210131'
  and event_name in ('add_shipping_info','add_to_cart','purchase')
group by 1,2
order by 1,2;

# Items check: add_shipping_info has empty items in all 19,722 events.
# add_to_cart and purchase carry items, but add_to_cart is missing for 41% of purchasers.
# Cart value / price of abandoned sessions cannot be measured reliably. Closed as a limitation.

# page paths at the leak.
# checking null
with cte as(
  select event_name, 
    (select value.string_value from unnest(event_params) where key = 'page_location') page_location
  from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  where _table_suffix between '20201101' and '20210131'
)
select count(*) from cte
where page_location is null or page_location = '(not set)';

with cte as(
  select event_name, 
    (select value.string_value from unnest(event_params) where key = 'page_location') page_location
  from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  where _table_suffix between '20201101' and '20210131'
)
select event_name,page_location, count(*) from cte
where event_name in ('add_shipping_info','add_payment_info')
group by 1,2;

# Page check: add_shipping_info fires on yourinfo.html (19,690 of 19,722 events), add_payment_info on payment.html (13,899).
# 32 shipping events sit on odd URLs (0.16%), treated as noise.
# Leak = drop between yourinfo.html and payment.html.

# Buckets of page location and their occurence for non-payers
with pv as(
  select  
    concat(user_pseudo_id,'-',cast((select value.int_value from unnest(event_params) where key = 'ga_session_id') as string)) session_id,
    event_timestamp,
    split((select value.string_value from unnest(event_params) where key = 'page_location'),'?')[offset(0)] page_location
  from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  where _table_suffix between '20201101' and '20210131'
    and event_name = 'page_view'
), nxt as(
  select
    b.session_id, pv.page_location, row_number() over(partition by b.session_id order by pv.event_timestamp) rn
  from pv
  right join `ca-analysis4.cart_abandonement_analysis.shipping_stay_base` b
    on b.session_id = pv.session_id
    and b.event_timestamp < pv.event_timestamp
  where b.reached_payment = 'non-payers'
), first_nxt as(
  select * from nxt where rn = 1
), bucket_group as(
  select
    case
      when page_location is null then 'No Next Page'
      when lower(page_location) like '%yourinfo%' then 'Same page (yourinfo)'
      when lower(page_location) like '%basket%' then 'Basket'
      when lower(page_location) like '%signin%'
        or lower(page_location) like '%myaccount%' then 'Sign-in / account'
      when lower(page_location) like '%store-policies%' THEN 'Policy / FAQ'
      when regexp_contains(lower(page_location), r'^https://(shop\.|www\.)?googlemerchandisestore\.com/?$') THEN 'Home'
      when lower(page_location) like '%google+redesign%'
        or lower(page_location) like '%store.html%' THEN 'Category / product'
      else 'Other'
    end as bucket
  from first_nxt
)
select
  bucket, count(*) sessions, round(count(*) / (select count(*) from first_nxt) * 100,2) pct  
from bucket_group
group by 1
order by 3 desc;

# Next page after yourinfo.html (non-payers, n=4,292): Home 42.5%, No next page 30.1%, Basket 9.25%, Same page 7.69%, Category/product 6.41%, Sign-in 1.98%, Policy 1.49%, Other 0.58%.
# Most non-payers left checkout for the homepage or opened no further page. Signs of form trouble, sign-in or policy questions are small. The data shows where they went, not why, so a fix needs an A/B test to verify.