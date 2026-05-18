-- tests/assert_no_orphan_options.sql
--
-- Options should only exist for known line items.
-- Flags referential integrity gaps between the two source tables.
-- Returns rows (failures) for any unmatched options.
 
select
    o.order_id,
    o.lineitem_id,
    o.option_name,
    o.option_price
from {{ ref('stg_order_item_options') }} o
left join {{ ref('stg_order_items') }} i
    on  o.order_id    = i.order_id
    and o.lineitem_id = i.lineitem_id
where i.lineitem_id is null
 
 