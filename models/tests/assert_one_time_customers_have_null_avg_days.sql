-- tests/assert_one_time_customers_have_null_avg_days.sql

select
    user_id,
    total_orders,
    avg_days_between_orders
from {{ ref('mart_loyalty_customer_metrics') }}
where total_orders = 1
  and avg_days_between_orders is not null
