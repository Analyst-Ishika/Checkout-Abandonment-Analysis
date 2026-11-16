# Created a table having one session per row 
create or replace table `ca-analysis4.cart_abandonement_analysis.session_funnel` as(
  with cte as(
    select
      session_id,
      max(event_step=1) has_checkout,
      max(event_step=2) has_ship,
      max(event_step=3) has_pay,
      max(event_step=4) has_purchase
    from `ca-analysis4.cart_abandonement_analysis.funnel_dedup`
    group by 1
  ), segment as(
    select 
      session_id, max(device_category) device_category, max(country) country, max(medium) medium, min(parse_date('%Y%m%d',event_date)) event_date
    from `ca-analysis4.cart_abandonement_analysis.funnel_dedup`
    group by 1
  )
  select 
    cte.session_id,
    cte.has_checkout reached_1,
    (cte.has_checkout and cte.has_ship) reached_2,
    (cte.has_checkout and cte.has_ship and cte.has_pay) reached_3,
    (cte.has_checkout and cte.has_ship and cte.has_pay and has_purchase) reached_4,
    s.event_date, s.device_category, s.country, s.medium
  from cte left join segment s
    on cte.session_id = s.session_id
  where cte.has_checkout
);

# Checked distinct values in segments
select session_id, count(distinct device_category), count(distinct country), count(distinct medium), count(distinct event_date)
from `ca-analysis4.cart_abandonement_analysis.funnel_dedup`
group by 1;

#Table - session_funnel
select * from `ca-analysis4.cart_abandonement_analysis.session_funnel`
limit 10;

select
  count(*) `rows`,
  count(distinct session_id) distinct_rows,
  min(event_date) min_date,
  max(event_date) max_date,
  countif(reached_1) r_1,  
  countif(reached_2) r_2,
  countif(reached_3) r_3,
  countif(reached_4) r_4
from `ca-analysis4.cart_abandonement_analysis.session_funnel`;

# Funnel Analysis
with `counts` as(
  select
    countif(reached_1) s1,
    countif(reached_2) s2,
    countif(reached_3) s3,
    countif(reached_4) s4
  from `ca-analysis4.cart_abandonement_analysis.session_funnel`
),steps as(
  select 1 step_no, 'begin_checkout' step, s1 sessions from counts
  union all select 2, 'add_shipping_info', s2 from counts
  union all select 3, 'add_payment_info', s3 from counts
  union all select 4, 'purchase', s4 from counts
)
select step_no, step, sessions,
  round(sessions / first_value(sessions) over(order by step_no) * 100,2) `reached_%`,
  round(sessions / lag(sessions) over(order by step_no) * 100,2) `%_of_previous`,
  (lag(sessions) over(order by step_no) - sessions) lost
from steps
# Of 11106 sessions that began checkout, 43.6% reached purchase, and the biggest drop was between add_shipping_info and add_payment_info, where 4292 sessions were lost.