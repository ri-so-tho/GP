-- tests/assert_line_total_matches_components.sql
--
-- Validates that line_total = item_revenue + total_option_revenue
-- within a $0.01 floating-point tolerance

select
    lineitem_id,
    line_total,
    item_revenue,
    total_option_revenue,
    line_total - (item_revenue + total_option_revenue) as discrepancy
from {{ ref('int_order_line_totals') }}
where abs(line_total - (item_revenue + total_option_revenue)) > 0.01
