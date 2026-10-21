CREATE DATABASE IF NOT EXISTS ecommerce_capstone;
USE ecommerce_capstone;

SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'items', COUNT(*) FROM items
UNION ALL
SELECT 'payments', COUNT(*) FROM payments
UNION ALL
SELECT 'reviews', COUNT(*) FROM reviews
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'category', COUNT(*) FROM category;

DESCRIBE orders;
DESCRIBE customers;
DESCRIBE items;
DESCRIBE payments;
DESCRIBE reviews;
DESCRIBE products;
DESCRIBE sellers;
DESCRIBE category;

-- 1. BUSINESS QUESTION: How many orders were placed each month?
SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS total_orders
FROM orders
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;


-- 2. BUSINESS QUESTION: What is the order status distribution?
SELECT
    order_status,
    COUNT(*) AS total_orders,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM orders), 2) AS pct_of_all_orders
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;


-- 3. BUSINESS QUESTION: What are total delivered item revenue and average item value per delivered order?
-- Aggregate items to one row per order before joining orders.
SELECT
    COUNT(*) AS delivered_orders,
    ROUND(SUM(item_totals.item_revenue), 2) AS delivered_item_revenue,
    ROUND(AVG(item_totals.item_revenue), 2) AS avg_item_value_per_delivered_order
FROM orders AS o
JOIN (
    SELECT order_id, SUM(price) AS item_revenue
    FROM items
    GROUP BY order_id
) AS item_totals
    ON o.order_id = item_totals.order_id
WHERE o.order_status = 'delivered';


-- 4. BUSINESS QUESTION: Which product categories generate the highest delivered item revenue?
SELECT
    COALESCE(c.product_category_name_english,
             p.product_category_name,
             'unknown') AS category_name,
    ROUND(SUM(i.price), 2) AS item_revenue,
    COUNT(DISTINCT i.order_id) AS orders_containing_category,
    SUM(i.order_item_id IS NOT NULL) AS item_rows
FROM items AS i
JOIN orders AS o
    ON i.order_id = o.order_id
JOIN products AS p
    ON i.product_id = p.product_id
LEFT JOIN category AS c
    ON p.product_category_name = c.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY COALESCE(c.product_category_name_english,
                  p.product_category_name,
                  'unknown')
ORDER BY item_revenue DESC
LIMIT 10;


-- 5. BUSINESS QUESTION: Which payment methods are most commonly used, and what payment value do they represent?
-- Payments are analysed independently from items to avoid duplicated sums.
SELECT
    payment_type,
    COUNT(*) AS payment_records,
    COUNT(DISTINCT order_id) AS orders_using_method,
    ROUND(SUM(payment_value), 2) AS total_payment_value,
    ROUND(AVG(payment_value), 2) AS avg_payment_record_value
FROM payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;


-- 6. BUSINESS QUESTION: What percentage of customers place more than one delivered order?
-- customer_unique_id groups repeat purchases by the same underlying customer.
WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS delivered_order_count
    FROM orders AS o
    JOIN customers AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*) AS customers_with_delivered_orders,
    SUM(delivered_order_count >= 2) AS repeat_customers,
    ROUND(100.0 * SUM(delivered_order_count >= 2) / COUNT(*), 2) AS repeat_customer_pct
FROM customer_order_counts;


-- 7. BUSINESS QUESTION: Which customer states have the most delivered orders?
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(DISTINCT c.customer_unique_id) AS distinct_customers
FROM orders AS o
JOIN customers AS c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY delivered_orders DESC;


-- 8. BUSINESS QUESTION: How many delivered orders arrived late, on time, or early?
SELECT
    CASE
        WHEN order_delivered_customer_date IS NULL
             OR order_estimated_delivery_date IS NULL THEN 'date_missing'
        WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'late'
        WHEN order_delivered_customer_date < order_estimated_delivery_date THEN 'early'
        ELSE 'on_time'
    END AS delivery_result,
    COUNT(*) AS order_count
FROM orders
WHERE order_status = 'delivered'
GROUP BY delivery_result
ORDER BY order_count DESC;


-- 9. BUSINESS QUESTION: What is the average delivery time and average delay versus estimate?
SELECT
    ROUND(AVG(TIMESTAMPDIFF(
        DAY, order_purchase_timestamp, order_delivered_customer_date
    )), 2) AS avg_days_from_purchase_to_delivery,
    ROUND(AVG(TIMESTAMPDIFF(
        DAY, order_estimated_delivery_date, order_delivered_customer_date
    )), 2) AS avg_days_vs_estimate
FROM orders
WHERE order_status = 'delivered'
  AND order_purchase_timestamp IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;


-- 10. BUSINESS QUESTION: What is the average review score and how many reviews are recorded per score?
SELECT
    review_score,
    COUNT(*) AS review_records
FROM reviews
WHERE review_score IS NOT NULL
GROUP BY review_score
ORDER BY review_score;


-- 11. BUSINESS QUESTION: Are late deliveries associated with different review scores?
-- This is descriptive association, not proof that delivery timing caused a score.
SELECT
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'late'
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 'on_time_or_early'
        ELSE 'delivery_date_missing'
    END AS delivery_result,
    COUNT(r.review_id) AS review_records,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders AS o
LEFT JOIN reviews AS r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY delivery_result
ORDER BY delivery_result;


-- 12. BUSINESS QUESTION: Which sellers have the highest delivered item revenue?
SELECT
    i.seller_id,
    COUNT(DISTINCT i.order_id) AS delivered_orders,
    COUNT(*) AS item_rows,
    ROUND(SUM(i.price), 2) AS item_revenue
FROM items AS i
JOIN orders AS o
    ON i.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY i.seller_id
ORDER BY item_revenue DESC
LIMIT 10;


-- 13. BUSINESS QUESTION: What are the monthly delivered order counts and item revenue?
-- Useful for a Power BI trend chart. Revenue excludes freight and is not profit.
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(SUM(i.price), 2) AS item_revenue
FROM orders AS o
JOIN items AS i
    ON o.order_id = i.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;


-- 14. BUSINESS QUESTION: What is the average order payment value?
-- First aggregate payment records to one row per order.
SELECT
    ROUND(AVG(order_payment_total), 2) AS avg_payment_value_per_order,
    ROUND(SUM(order_payment_total), 2) AS total_payment_value
FROM (
    SELECT order_id, SUM(payment_value) AS order_payment_total
    FROM payments
    GROUP BY order_id
) AS payment_totals;


-- 15. VALIDATION: Do the core tables have the expected row counts?
SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'items', COUNT(*) FROM items
UNION ALL SELECT 'payments', COUNT(*) FROM payments
UNION ALL SELECT 'reviews', COUNT(*) FROM reviews
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'category', COUNT(*) FROM category;

