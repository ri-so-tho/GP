-- tests/assert_customer_segment_matches_order_count.sql
--
-- Validates that customer_segment labels are consistent with
-- the total_orders thresholds defined in mart_loyalty_customer_metrics.
-- Catches any drift if thresholds are edited without updating the CASE logic.

select
    user_id,
    total_orders,
    customer_segment
from {{ ref('mart_loyalty_customer_metrics') }}
where
    (total_orders >= 20 and customer_segment != 'Champion')
    or (total_orders >= 10 and total_orders < 20 and customer_segment != 'Loyal')
    or (total_orders >= 5  and total_orders < 10 and customer_segment != 'Regular')
    or (total_orders >= 2  and total_orders < 5  and customer_segment != 'Returning')
    or (total_orders  = 1  and customer_segment != 'One-Time')
