-- example_loyalty_customer_metrics.sql
-- This model attempts to build a loyalty customer summary with lifetime metrics
-- for the Alltown Fresh mobile ordering platform.

WITH loyalty_customers AS (
    SELECT
        user_id,
        printed_card_number,
        restaurant_id,
        MIN(creation_time_utc) AS first_order_date,
        MAX(creation_time_utc) AS last_order_date,
        COUNT(DISTINCT order_id) AS total_orders,
        COUNT(DISTINCT restaurant_id) AS unique_locations,
        SUM(item_price) AS lifetime_spend
    FROM order_items
    WHERE is_loyalty = TRUE
    GROUP BY user_id, printed_card_number, restaurant_id
    -- ***********NEW
    SELECT
        user_id,
        printed_card_number,
        -- restaurant_id
        MIN(creation_time_utc) AS first_order_date,
        MAX(creation_time_utc) AS last_order_date,
        COUNT(DISTINCT order_id) AS total_orders,
        COUNT(DISTINCT restaurant_id) AS unique_locations,
        SUM(item_price) AS lifetime_spend
    FROM order_items
    WHERE is_loyalty = TRUE
    GROUP BY user_id, printed_card_number  -- ,restaurant_id
    
),

order_details AS (
    SELECT
        oi.order_id,
        oi.user_id,
        oi.restaurant_id,
        oi.creation_time_utc,
        oi.item_category,
        oi.item_name,
        oi.item_price,
        oi.item_quantity,
        oio.option_name,
        oio.option_price,
        oio.option_quantity,
        oi.item_price * oi.item_quantity + oio.option_price * oio.option_quantity AS line_total,
        ROW_NUMBER() OVER(PARTITION BY oi.order_id ORDER BY oi.creation_time_utc) AS item_rank,
        RANK() OVER(PARTITION BY oi.user_id ORDER BY oi.creation_time_utc) AS visit_number
    FROM order_items oi
    LEFT JOIN order_item_options oio ON oi.order_id = oio.order_id
    WHERE oi.app_name = 'Alltown Fresh'
    -- ***********NEW
    SELECT
        oi.order_id,
        oi.user_id,
        oi.restaurant_id,
        oi.creation_time_utc,
        oi.item_category,
        oi.item_name,
        oi.item_price,
        oi.item_quantity,
        oio.option_name,
        oio.option_price,
        oio.option_quantity,
        oi.item_price * oi.item_quantity + COALESCE(oio.option_price, 0) * COALESCE(oio.option_quantity, 0) AS line_total,
        ROW_NUMBER() OVER(PARTITION BY oi.order_id ORDER BY oi.creation_time_utc) AS item_rank,
        DENSE_RANK() OVER(PARTITION BY oi.user_id ORDER BY oi.creation_time_utc) AS visit_number
    FROM order_items oi
    LEFT JOIN order_item_options oio ON oi.order_id = oio.order_id AND oi.lineitem_id = oio.lineitem_id
    WHERE oi.app_name = 'Alltown Fresh' 
    -- and user_id is not null
    -- item_rank and visit_number not used anywhere
    ORDER BY user_id, creation_time_utc, item_rank, visit_number
),

customer_segments AS (
    SELECT
        user_id,
        CASE
            WHEN total_orders >= 20 THEN 'Champion'
            WHEN total_orders >= 10 THEN 'Loyal'
            WHEN total_orders >= 5 THEN 'Regular'
            WHEN total_orders >= 2 THEN 'Returning'
            ELSE 'One-Time'
        END AS customer_segment,
        CASE
            WHEN DATEDIFF('day', last_order_date, CURRENT_DATE()) <= 30 THEN 'Active'
            WHEN DATEDIFF('day', last_order_date, CURRENT_DATE()) <= 90 THEN 'At Risk'
            WHEN DATEDIFF('day', last_order_date, CURRENT_DATE()) <= 180 THEN 'Lapsing'
            ELSE 'Churned'
        END AS recency_status,
        lifetime_spend,
        lifetime_spend / total_orders AS avg_order_value,
        DATEDIFF('day', first_order_date, last_order_date) / total_orders AS avg_days_between_orders
    FROM loyalty_customers
),

category_preferences AS (
    SELECT
        user_id,
        item_category,
        COUNT(*) AS category_orders,
        SUM(line_total) AS category_spend,
        ROW_NUMBER() OVER(PARTITION BY user_id ORDER BY COUNT(*) DESC) AS category_rank
    FROM order_details
    GROUP BY user_id, item_category
),

monthly_trends AS (
    SELECT
        user_id,
        DATE_TRUNC('month', creation_time_utc) AS order_month,
        COUNT(DISTINCT order_id) AS monthly_orders,
        SUM(line_total) AS monthly_spend,
        LAG(SUM(line_total)) OVER(PARTITION BY user_id ORDER BY order_month) AS prev_month_spend
    FROM order_details
    GROUP BY user_id, DATE_TRUNC('month', creation_time_utc)
),

final AS (
   --  SELECT
--         cs.user_id,
--         cs.customer_segment,
--         cs.recency_status,
--         cs.lifetime_spend,
--         cs.avg_order_value,
--         cs.avg_days_between_orders,
--         cp.item_category AS top_category,
--         cp.category_spend AS top_category_spend,
--         lc.total_orders,
--         lc.unique_locations,
--         lc.first_order_date,
--         lc.last_order_date
--     FROM customer_segments cs
--     LEFT JOIN category_preferences cp ON cs.user_id = cp.user_id AND cp.category_rank = 1
--     LEFT JOIN loyalty_customers lc ON cs.user_id = lc.user_id
--     LEFT JOIN monthly_trends mt ON cs.user_id = mt.user_id
    -- ***************NEW
    SELECT
        DISTINCT
        cs.user_id,
        cs.customer_segment,
        cs.recency_status,
        cs.lifetime_spend,
        cs.avg_order_value,
        cs.avg_days_between_orders,
        cp.item_category AS top_category,
        cp.category_spend AS top_category_spend,
        lc.total_orders,
        lc.unique_locations,
        lc.first_order_date,
        lc.last_order_date,
    FROM customer_segments cs
    LEFT JOIN category_preferences cp ON cs.user_id = cp.user_id AND cp.category_rank = 1
    LEFT JOIN loyalty_customers lc ON cs.user_id = lc.user_id
)

SELECT *
FROM final
ORDER BY lifetime_spend DESC;
