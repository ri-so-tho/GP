
-- ************************BUG 1: GROUP BY restaurant_id inflates loyalty_customers

-- Bug: produces one row per user+restaurant (6,236 rows)
SELECT
    user_id,
    COUNT(DISTINCT restaurant_id) AS unique_locations   -- always = 1
FROM order_items
WHERE is_loyalty = TRUE
GROUP BY user_id, printed_card_number, restaurant_id;

-- Correct: one row per user (5,869 rows)
SELECT
    user_id,
    COUNT(DISTINCT restaurant_id) AS unique_locations   -- reflects real multi-location visits
FROM order_items
WHERE is_loyalty = TRUE
GROUP BY user_id, printed_card_number;

-- Impact: how many phantom rows and how many users are miscounted
SELECT
    COUNT(*)                          AS buggy_rows,    -- 6,236
    COUNT(DISTINCT user_id)           AS correct_rows,  -- 5,869
    COUNT(*) - COUNT(DISTINCT user_id) AS phantom_rows  -- 367
FROM order_items
WHERE is_loyalty = TRUE
GROUP BY user_id, printed_card_number, restaurant_id;

-- ************************BUG 2: JOIN on order_id only → row explosion + inflated spend

-- Row count comparison
SELECT 'buggy'   AS version, COUNT(*) AS row_count
FROM order_items oi
LEFT JOIN order_item_options oio ON oi.order_id = oio.order_id

UNION ALL

SELECT 'correct' AS version, COUNT(*) AS row_count
FROM order_items oi
LEFT JOIN order_item_options oio
    ON oi.order_id   = oio.order_id
    AND oi.lineitem_id = oio.lineitem_id;
-- bug: 478,358 rows  |  correct: 289,779 rows

-- Revenue overstatement from the bad join
SELECT
    SUM(oi.item_price * oi.item_quantity
        + COALESCE(oio.option_price, 0) * COALESCE(oio.option_quantity, 0)
    )                                           AS buggy_total_revenue,  -- $72.6M
    -- correct total (for comparison — run the correct join separately)
    -- correct: $18.0M
    COUNT(*) - COUNT(DISTINCT oi.lineitem_id)   AS duplicate_rows_created -- 188,579
FROM order_items oi
LEFT JOIN order_item_options oio ON oi.order_id = oio.order_id;


-- ************************BUG 3: No COALESCE → line_total is NULL for items with no options

-- How many rows get a NULL line_total
SELECT
    COUNT(*)                                                        AS total_rows,
    SUM(CASE WHEN oio.option_price IS NULL THEN 1 ELSE 0 END)      AS null_line_total_rows,   -- 100,822
    ROUND(
        100.0 * SUM(CASE WHEN oio.option_price IS NULL THEN 1 ELSE 0 END)
        / COUNT(*), 1
    )                                                               AS pct_null               -- 34.3%
FROM order_items oi
LEFT JOIN order_item_options oio
    ON oi.order_id = oio.order_id AND oi.lineitem_id = oio.lineitem_id;

-- Revenue dropped because NULL propagates through SUM
SELECT
    SUM(oi.item_price * oi.item_quantity
        + oio.option_price * oio.option_quantity)                   AS buggy_revenue,    -- $9.97M
    SUM(oi.item_price * oi.item_quantity
        + COALESCE(oio.option_price, 0) * COALESCE(oio.option_quantity, 0))
                                                                    AS correct_revenue,  -- $18.04M
    SUM(oi.item_price * oi.item_quantity
        + COALESCE(oio.option_price, 0) * COALESCE(oio.option_quantity, 0))
    - SUM(oi.item_price * oi.item_quantity
        + oio.option_price * oio.option_quantity)                   AS revenue_lost      -- $8.07M
FROM order_items oi
LEFT JOIN order_item_options oio
    ON oi.order_id = oio.order_id AND oi.lineitem_id = oio.lineitem_id;


-- ************************BUG 4: monthly_trends joined in final → row fan-out

-- Show that monthly_trends has multiple rows per user
SELECT
    user_id,
    COUNT(DISTINCT DATE_TRUNC('month', creation_time_utc)) AS months_active
FROM order_items
WHERE is_loyalty = TRUE AND user_id IS NOT NULL
GROUP BY user_id
ORDER BY months_active DESC
LIMIT 5;
-- Top users have 12 months → their row gets duplicated 12×

-- Measure the fan-out: correct rows vs buggy rows in final
SELECT 'correct' AS version, COUNT(DISTINCT user_id) AS rows
FROM order_items WHERE is_loyalty = TRUE AND user_id IS NOT NULL

UNION ALL

SELECT 'buggy' AS version, COUNT(*) AS rows
FROM (
    SELECT DISTINCT oi.user_id, mt.order_month
    FROM (
        SELECT user_id FROM order_items
        WHERE is_loyalty = TRUE AND user_id IS NOT NULL
        GROUP BY user_id
    ) oi
    JOIN (
        SELECT user_id, DATE_TRUNC('month', creation_time_utc) AS order_month
        FROM order_items WHERE is_loyalty = TRUE AND user_id IS NOT NULL
        GROUP BY user_id, DATE_TRUNC('month', creation_time_utc)
    ) mt ON oi.user_id = mt.user_id
);
-- correct: 5,829  |  bug: 14,671  (2.5× fan-out)


-- ************************BUG 5: RANK() creates gaps in visit_number

-- Side-by-side comparison of RANK vs DENSE_RANK for a single user
SELECT
    order_id,
    creation_time_utc,
    RANK()       OVER (PARTITION BY user_id ORDER BY DATE_TRUNC('day', creation_time_utc)) AS visit_rank,   -- 1,3,5,7...
    DENSE_RANK() OVER (PARTITION BY user_id ORDER BY DATE_TRUNC('day', creation_time_utc)) AS visit_dense  -- 1,2,3,4...
FROM order_items
WHERE user_id = '609d681462e498b356e72a6d'  -- example user with gaps
ORDER BY creation_time_utc;

-- Count how many rows are affected across all loyalty customers
SELECT
    SUM(CASE WHEN visit_rank != visit_dense THEN 1 ELSE 0 END)     AS rows_with_gaps,  -- 28,903
    COUNT(*)                                                         AS total_rows,
    ROUND(100.0 *
        SUM(CASE WHEN visit_rank != visit_dense THEN 1 ELSE 0 END)
        / COUNT(*), 1)                                              AS pct_affected     -- 62.8%
FROM (
    SELECT
        RANK()       OVER (PARTITION BY user_id ORDER BY DATE_TRUNC('day', creation_time_utc)) AS visit_rank,
        DENSE_RANK() OVER (PARTITION BY user_id ORDER BY DATE_TRUNC('day', creation_time_utc)) AS visit_dense
    FROM order_items
    WHERE is_loyalty = TRUE AND user_id IS NOT NULL
);


-- ************************DATA QUALITY 1: Ghost row

SELECT order_id, item_name, item_price, item_quantity, lineitem_id
FROM order_items
WHERE lineitem_id IS NULL OR item_quantity = 0;
-- 1 row: qty=0, all fields NULL — failed transaction never completed


-- ************************DATA QUALITY 2: Development app traffic

SELECT
    app_name,
    COUNT(*)                  AS rows,
    COUNT(DISTINCT order_id)  AS orders,
    SUM(item_price)           AS revenue,
    SUM(CASE WHEN is_loyalty THEN 1 ELSE 0 END) AS loyalty_rows
FROM order_items
WHERE app_name ILIKE '%development%'
GROUP BY app_name;
-- 826 rows | 741 orders | $7,221 test revenue | 437 loyalty rows


-- ************************DATA QUALITY 3: Duplicate rows in order_item_options
SELECT
    COUNT(*)                                             AS total_rows,       -- 193,017
    COUNT(*) - COUNT(DISTINCT order_id || lineitem_id
                     || option_group_name || option_name
                     || option_price || option_quantity) AS duplicate_rows,   -- 2,299
    SUM(option_price * option_quantity)                  AS revenue_with_dupes,
    -- deduplicated revenue for comparison:
    -- run same query after QUALIFY ROW_NUMBER()=1
    COUNT(DISTINCT order_id || lineitem_id
          || option_group_name || option_name
          || option_price || option_quantity)            AS unique_option_combos
FROM order_item_options;


-- ************************DATA QUALITY 4: Loyalty orders with NULL user_id

SELECT
    COUNT(*)                  AS rows,    -- 28
    COUNT(DISTINCT order_id)  AS orders,  -- 18
    SUM(item_price)           AS revenue  -- $274.18 unattributable
FROM order_items
WHERE is_loyalty = TRUE AND user_id IS NULL;


-- ************************DATA QUALITY 5: Orphan options (no matching order in order_items)

SELECT
    COUNT(*)                             AS orphan_rows,    -- 28
    COUNT(DISTINCT oio.order_id)         AS orphan_orders,  -- 14
    SUM(oio.option_price * oio.option_quantity) AS revenue  -- $24.00
FROM order_item_options oio
LEFT JOIN order_items oi ON oio.order_id = oi.order_id
WHERE oi.order_id IS NULL;


-- ************************DATA QUALITY 6: Implausibly large orders

SELECT
    order_id,
    item_name,
    item_price,
    item_quantity,
    item_price * item_quantity AS line_revenue
FROM order_items
WHERE item_price > 500 OR item_quantity > 200
ORDER BY item_price * item_quantity DESC;
