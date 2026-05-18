-- models/marts/loyalty/mart_loyalty_monthly_trends.sql
--
-- Monthly spend trends per loyalty customer.
-- Split from mart_loyalty_customer_metrics to avoid row fan-out in the
-- customer-level mart (one row per user per month ≠ one row per user).
--
-- Consumers: BI dashboards, month-over-month spend charts.

with monthly as (

    select
        user_id,
        date_trunc('month', created_at) as order_month,
        count(distinct order_id)        as monthly_orders,
        sum(line_total)                 as monthly_spend

    from {{ ref('int_order_line_totals') }}

    where is_loyalty = true
      and user_id is not null

    group by user_id, date_trunc('month', created_at)

),

with_lag as (

    select
        user_id,
        order_month,
        monthly_orders,
        monthly_spend,

        lag(monthly_spend) over (
            partition by user_id
            order by order_month
        ) as prev_month_spend,

        monthly_spend - lag(monthly_spend) over (
            partition by user_id
            order by order_month
        ) as spend_delta,

        -- Month-over-month growth rate; null-safe for first month
        case
            when lag(monthly_spend) over (
                     partition by user_id order by order_month
                 ) = 0 then null
            else (
                monthly_spend - lag(monthly_spend) over (
                    partition by user_id order by order_month
                )
            ) / lag(monthly_spend) over (
                    partition by user_id order by order_month
                )
        end as spend_mom_growth_rate

    from monthly

)

select * from with_lag
order by user_id, order_month
