-- tests/assert_monthly_trends_covers_all_customers.sql

select
    cm.user_id
from {{ ref('mart_loyalty_customer_metrics') }} cm
left join {{ ref('mart_loyalty_monthly_trends') }} mt
    on cm.user_id = mt.user_id
where mt.user_id is null
