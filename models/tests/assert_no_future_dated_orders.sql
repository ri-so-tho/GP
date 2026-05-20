-- tests/assert_no_future_dated_orders.sql

select
    order_id,
    lineitem_id,
    created_at
from {{ ref('stg_order_items') }}
where created_at > current_timestamp()
