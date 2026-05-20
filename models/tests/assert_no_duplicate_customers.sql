-- tests/assert_no_duplicate_customers.sql
--
-- A user should appear in mart_loyalty_customer_metrics exactly once

select
    user_id,
    count(*) as row_count
from {{ ref('mart_loyalty_customer_metrics') }}
group by user_id
having count(*) > 1
