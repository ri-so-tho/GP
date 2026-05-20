-- tests/assert_lifetime_spend_matches_monthly_rollup.sql
--
-- Validates that lifetime_spend in the customer mart equals the
-- sum of monthly_spend in the trends mart for every user.
-- A mismatch means the two models have diverged in their filter
-- logic or aggregation.

select
    cm.user_id,
    cm.lifetime_spend,
    sum(mt.monthly_spend)                             as monthly_rollup,
    abs(cm.lifetime_spend - sum(mt.monthly_spend))    as discrepancy
from {{ ref('mart_loyalty_customer_metrics') }} cm
left join {{ ref('mart_loyalty_monthly_trends') }} mt
    on cm.user_id = mt.user_id
group by cm.user_id, cm.lifetime_spend
having abs(cm.lifetime_spend - sum(mt.monthly_spend)) > 0.01
