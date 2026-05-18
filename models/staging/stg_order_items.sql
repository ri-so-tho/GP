-- models/staging/stg_order_items.sql
--
-- Cleans and standardises the raw order_items source.
-- One row per line item. Filters out ghost rows and test/dev traffic.
-- All downstream models should reference this, never the raw table.

with source as (

    select * from {{ source('alltown', 'order_items') }}

),

cleaned as (

    select
        app_name,
        restaurant_id,
        order_id,
        lineitem_id,
        user_id,
        printed_card_number,

        -- Normalise the ISO-8601 timestamp to a proper timestamp type
        try_cast(creation_time_utc as timestamp) as created_at,

        is_loyalty,
        currency,
        item_category,
        item_name,
        item_price,
        item_quantity,

        -- Derived: true economic value of the line item (base price only;
        -- option revenue is added in int_order_line_totals)
        item_price * item_quantity as item_revenue

    from source

    where
        -- Remove the single ghost row (no lineitem, zero quantity)
        lineitem_id is not null
        and item_quantity > 0

        -- Exclude internal development traffic
        and app_name not ilike '%development%'

        -- Exclude implausibly large orders (likely test / data-entry errors).
        -- Threshold: quantity > 200 or unit price > $500 flagged for review.
        and item_quantity <= 200
        and item_price <= 500

)

select * from cleaned
