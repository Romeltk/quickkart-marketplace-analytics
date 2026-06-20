# 1) Monthly marketplace metrics



WITH order_gmv AS (
    SELECT
        oi.order_id,
        SUM(oi.quantity * oi.unit_price) AS gmv
    FROM order_items oi
    GROUP BY oi.order_id
),

delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.created_at,
        DATE_TRUNC('month', o.created_at) AS month,
        c.city,
        ROW_NUMBER() OVER (
            PARTITION BY o.customer_id
            ORDER BY o.created_at
        ) AS delivered_order_num
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    WHERE o.status = 'Delivered'
),

monthly_metrics AS (
    SELECT
        d.month,
        d.city,

        SUM(g.gmv) AS gmv,

        COUNT(DISTINCT d.order_id) AS number_of_orders,

        COUNT(DISTINCT d.customer_id) AS unique_customers,

        COUNT(
            DISTINCT CASE
                WHEN d.delivered_order_num >= 2
                THEN d.customer_id
            END
        ) AS repeat_customers

    FROM delivered_orders d
    JOIN order_gmv g
        ON g.order_id = d.order_id
    GROUP BY 1,2
)

SELECT
    month,
    city,
    gmv,
    number_of_orders,
    unique_customers,

    ROUND(
        repeat_customers::numeric
        / NULLIF(unique_customers,0),
        4
    ) AS repeat_purchase_rate

FROM monthly_metrics
ORDER BY month, city;

# --------------------------------------------------------------------------
# 2) Impact of First Order delay on repeat

WITH first_delivered_order AS (

    SELECT *
    FROM (

        SELECT
            o.customer_id,
            o.order_id,
            o.created_at,

            CASE
                WHEN s.delivery_status = 'OnTime'
                THEN 'OnTime'
                ELSE 'Delayed'
            END AS first_order_delay_status,

            ROW_NUMBER() OVER (
                PARTITION BY o.customer_id
                ORDER BY o.created_at
            ) AS rn

        FROM orders o
        JOIN shipments s
            ON s.order_id = o.order_id

        WHERE o.status = 'Delivered'

    ) x

    WHERE rn = 1
),

repeat_within_90d AS (

    SELECT
        f.customer_id,
        f.first_order_delay_status,

        CASE
            WHEN EXISTS (

                SELECT 1
                FROM orders o2

                WHERE o2.customer_id = f.customer_id
                  AND o2.status = 'Delivered'
                  AND o2.created_at > f.created_at
                  AND o2.created_at <= f.created_at + INTERVAL '90 day'

            )
            THEN 1
            ELSE 0
        END AS repeated_within_90d

    FROM first_delivered_order f
)

SELECT
    first_order_delay_status,

    ROUND(
        AVG(repeated_within_90d)::numeric,
        4
    ) AS repeat_rate_90d

FROM repeat_within_90d

GROUP BY first_order_delay_status;

# ----------------------------------------------------------------------------

# 3) Seller carrier performance

WITH base AS (

    SELECT

        oi.seller_id,
        s.carrier,
        s.ship_to_city,

        o.order_id,

        (oi.quantity * oi.unit_price) AS item_gmv,

        CASE
            WHEN s.delivery_status <> 'OnTime'
            THEN 1
            ELSE 0
        END AS is_delayed,

        CASE
            WHEN s.delivery_status <> 'OnTime'
            THEN (
                s.delivered_at::date
                - o.promised_delivery_date::date
            )
        END AS delay_days

    FROM order_items oi

    JOIN orders o
        ON o.order_id = oi.order_id

    JOIN shipments s
        ON s.order_id = o.order_id

    WHERE o.status = 'Delivered'
)

SELECT

    seller_id,
    carrier,
    ship_to_city,

    SUM(item_gmv) AS total_gmv,

    SUM(
        CASE
            WHEN is_delayed = 1
            THEN item_gmv
            ELSE 0
        END
    ) AS delayed_gmv,

    ROUND(
        AVG(is_delayed::numeric),
        4
    ) AS delayed_order_rate,

    ROUND(
        AVG(delay_days),
        2
    ) AS avg_delay_days

FROM base

GROUP BY
    seller_id,
    carrier,
    ship_to_city

HAVING COUNT(DISTINCT order_id) >= 100

ORDER BY delayed_order_rate DESC;

# --------------------------------------------------------------------------

# 4) Query optimization

# Given query

SELECT o.order_id,
(
    SELECT delivered_at
    FROM shipments s
    WHERE s.order_id = o.order_id
) AS delivered_at,
o.created_at,
c.city
FROM orders o
JOIN customers c
ON c.customer_id = o.customer_id
WHERE EXISTS (
    SELECT 1
    FROM shipments s2
    WHERE s2.order_id = o.order_id
      AND s2.delivery_status <> 'OnTime'
);

# Optimized query

SELECT

    o.order_id,
    s.delivered_at,
    o.created_at,
    c.city

FROM orders o

JOIN customers c
    ON c.customer_id = o.customer_id

JOIN shipments s
    ON s.order_id = o.order_id

WHERE s.delivery_status <> 'OnTime';

# The given query performs a subquery for each order to check the delivery status, which can be inefficient. The optimized query uses a direct JOIN to filter orders based on the delivery status, reducing the number of subqueries and improving performance.

# What indexes would you add to support your queries, and how would they help?
# To optimize the performance of the queries, I would add the following indexes:
1) index on orders(customer_id, created_at)
2) index on shipments(order_id)
3) index on order_items(order_id);