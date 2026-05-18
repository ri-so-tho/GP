-- tests/assert_no_duplicate_customers.sql
--
-- A user should appear in mart_loyalty_customer_metrics exactly once.
-- This catches any join that accidentally fans out the customer grain.
-- Returns rows (failures) if any user_id appears more than once.

select
    user_id,
    count(*) as row_count
from {{ ref('mart_loyalty_customer_metrics') }}
group by user_id
having count(*) > 1
