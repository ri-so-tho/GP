-- models/marts/loyalty/mart_loyalty_customer_metrics.sql
--
-- One row per loyalty customer.
-- Aggregates lifetime metrics, segments, recency status, top category,
-- and month-over-month spend trends.
--
-- Key fixes vs the original query
-- --------------------------------
-- 1. loyalty_customers no longer groups by restaurant_id, so
--    unique_locations and lifetime aggregates are truly per-user.
-- 2. customer_segments reads from the corrected loyalty_customers CTE.
-- 3. DATEDIFF arguments verified: (start, end) = (last_order, today)
--    produces positive day counts.
-- 4. avg_days_between_orders guards against division by zero (1-order users).
-- 5. monthly_trends join removed from final — it added no selected columns
--    and caused a row fan-out.  Monthly data is surfaced as a separate
--    mart (mart_loyalty_monthly_trends) for BI tool consumption.
-- 6. category_preferences is built on int_order_line_totals, not the
--    raw fan-out join, so spend figures are correct.

with loyalty_customers as (

    -- Lifetime summary per user — one row per user, not per user+restaurant.
    select
        user_id,
        printed_card_number,
        min(created_at)                     as first_order_at,
        max(created_at)                     as last_order_at,
        count(distinct order_id)            as total_orders,
        count(distinct restaurant_id)       as unique_locations,
        sum(line_total)                     as lifetime_spend,
        sum(item_revenue)                   as lifetime_item_revenue,
        sum(total_option_revenue)           as lifetime_option_revenue

    from {{ ref('int_order_line_totals') }}

    where is_loyalty = true
      and user_id is not null  -- 28 loyalty rows have no user_id; exclude them
                               -- as they cannot be attributed to a customer

    group by user_id, printed_card_number

),

customer_segments as (

    select
        user_id,
        printed_card_number,
        first_order_at,
        last_order_at,
        total_orders,
        unique_locations,
        lifetime_spend,
        lifetime_item_revenue,
        lifetime_option_revenue,

        -- Engagement tier based on total order count
        case
            when total_orders >= 20 then 'Champion'
            when total_orders >= 10 then 'Loyal'
            when total_orders >= 5  then 'Regular'
            when total_orders >= 2  then 'Returning'
            else                         'One-Time'
        end as customer_segment,

        -- Recency status based on days since last order
        -- datediff(start, end) → positive integer when end > start
        case
            when datediff('day', last_order_at, current_date()) <= 30  then 'Active'
            when datediff('day', last_order_at, current_date()) <= 90  then 'At Risk'
            when datediff('day', last_order_at, current_date()) <= 180 then 'Lapsing'
            else                                                             'Churned'
        end as recency_status,

        -- Average spend per order
        lifetime_spend / total_orders as avg_order_value,

        -- Average days between visits; guard against single-order users
        -- where first = last (result would be 0, which is technically correct
        -- but misleading — surfaced as null instead)
        case
            when total_orders = 1 then null
            else datediff('day', first_order_at, last_order_at)
                     / nullif(total_orders - 1, 0)
        end as avg_days_between_orders

    from loyalty_customers

),

category_preferences as (

    -- Top item category per loyalty user by order frequency.
    -- Built on int_order_line_totals so line_total is correct.
    select
        user_id,
        item_category,
        count(distinct order_id) as category_order_count,
        sum(line_total)          as category_spend,

        row_number() over (
            partition by user_id
            order by count(distinct order_id) desc, sum(line_total) desc
        ) as category_rank  -- tie-break: higher spend wins

    from {{ ref('int_order_line_totals') }}

    where is_loyalty = true
      and user_id is not null
      and item_category is not null

    group by user_id, item_category

),

final as (

    select
        cs.user_id,
        cs.printed_card_number,
        cs.customer_segment,
        cs.recency_status,
        cs.total_orders,
        cs.unique_locations,
        cs.first_order_at,
        cs.last_order_at,
        cs.lifetime_spend,
        cs.lifetime_item_revenue,
        cs.lifetime_option_revenue,
        cs.avg_order_value,
        cs.avg_days_between_orders,
        cp.item_category  as top_category,
        cp.category_spend as top_category_spend

    from customer_segments cs
    left join category_preferences cp
        on cs.user_id = cp.user_id
        and cp.category_rank = 1

)

select * from final
order by lifetime_spend desc
