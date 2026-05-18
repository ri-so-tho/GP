-- models/staging/stg_order_item_options.sql
--
-- Cleans raw order_item_options.
-- Deduplicates exact duplicate rows (double-submission artefacts).
-- One row per distinct option per line item.

with source as (

    select * from {{ source('alltown', 'order_item_options') }}

),

-- Remove exact duplicate rows introduced by double-submission bugs.
-- qualify keeps only the first physical occurrence of each logical record.
deduped as (

    select
        order_id,
        lineitem_id,
        option_group_name,
        option_name,
        option_price,
        option_quantity

    from source

    qualify
        row_number() over (
            partition by order_id, lineitem_id, option_group_name, option_name,
                         option_price, option_quantity
            order by 1   -- arbitrary but deterministic tie-break
        ) = 1

)

select * from deduped
