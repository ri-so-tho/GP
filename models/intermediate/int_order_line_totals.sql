-- models/intermediate/int_order_line_totals.sql
--
-- Joins cleaned line items with their options and produces a single
-- monetary total per line item. This is the canonical "what did
-- one item + its modifiers cost?" model.
--
-- Key fixes vs the original query
-- --------------------------------
-- 1. JOIN uses (order_id, lineitem_id) — not order_id alone — to avoid
--    a cartesian fan-out across items within the same order.
-- 2. COALESCE wraps option values so items with no options still get
--    a non-null line_total.
-- 3. DENSE_RANK used for visit_number so ties don't create gaps.

with items as (

    select * from {{ ref('stg_order_items') }}

),

options_aggregated as (

    -- Roll options up to lineitem grain before joining.
    -- This prevents one row per option appearing in the output.
    select
        order_id,
        lineitem_id,
        sum(option_price * option_quantity) as total_option_revenue,
        count(*)                            as option_count

    from {{ ref('stg_order_item_options') }}

    group by order_id, lineitem_id

),

joined as (

    select
        i.app_name,
        i.restaurant_id,
        i.order_id,
        i.lineitem_id,
        i.user_id,
        i.printed_card_number,
        i.created_at,
        i.is_loyalty,
        i.currency,
        i.item_category,
        i.item_name,
        i.item_price,
        i.item_quantity,
        i.item_revenue,

        coalesce(o.total_option_revenue, 0) as total_option_revenue,
        coalesce(o.option_count, 0)         as option_count,

        -- True line total: base + options
        i.item_revenue + coalesce(o.total_option_revenue, 0) as line_total,

        -- Position of this item within its order (for basket analysis)
        row_number() over (
            partition by i.order_id
            order by i.created_at, i.lineitem_id
        ) as item_rank_in_order,

        -- Customer visit number (dense so ties don't produce gaps)
        dense_rank() over (
            partition by i.user_id
            order by date_trunc('day', i.created_at)
        ) as customer_visit_number

    from items i
    left join options_aggregated o
        on i.order_id   = o.order_id
        and i.lineitem_id = o.lineitem_id

)

select * from joined
