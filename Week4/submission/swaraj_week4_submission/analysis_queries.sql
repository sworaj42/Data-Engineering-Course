-- ═══════════════════════════════════════════════════════════════════
-- Week 4 Assignment — Ride-Sharing Warehouse Analysis Queries
-- Swaraj Sigdel
--
-- Tasks 3, 4, 5 — analytical queries against the ride_dw warehouse
-- (Task 3 also includes the equivalent OLTP query against ride_prod)
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- TASK 3 — Revenue by city and month
-- ═══════════════════════════════════════════════════════════════════

-- ── Warehouse version (run against ride_dw) ────────────────────────
-- Uses pre-computed fare_amount and the pre-built dim_date dimension.
SELECT
    dl.city_name,
    dd.year,
    dd.month,
    dd.month_name,
    SUM(ft.fare_amount) AS total_revenue
FROM fact_trips ft
JOIN dim_location dl ON ft.pickup_location_key = dl.location_key
JOIN dim_date dd     ON ft.date_key = dd.date_key
GROUP BY dl.city_name, dd.year, dd.month, dd.month_name
ORDER BY dl.city_name, dd.year, dd.month;


-- ── OLTP version (run against ride_prod) ───────────────────────────
-- The fare must be computed manually and year/month extracted from
-- the raw timestamp, since the OLTP schema stores neither pre-computed.
SELECT
    l.city_name,
    EXTRACT(YEAR FROM t.requested_at)  AS year,
    EXTRACT(MONTH FROM t.requested_at) AS month,
    SUM((t.base_fare * t.surge_multiplier) + t.tip_amount - t.discount_amount) AS total_revenue
FROM trips t
JOIN locations l ON t.pickup_location_id = l.location_id
GROUP BY l.city_name, EXTRACT(YEAR FROM t.requested_at), EXTRACT(MONTH FROM t.requested_at)
ORDER BY l.city_name, year, month;

-- ── Answer ─────────────────────────────────────────────────────────
-- Warehouse version: 2 joins (dim_location + dim_date)
-- OLTP version: 1 join (locations)
--
-- The OLTP version needed fewer joins, but I had to manually calculate
-- the fare (base × surge + tip − discount) and extract year/month from
-- the timestamp. In the warehouse these were already pre-computed during
-- ETL, so the query was simpler even with one extra join.


-- ═══════════════════════════════════════════════════════════════════
-- TASK 4 — Payment method revenue (run against ride_dw)
-- ═══════════════════════════════════════════════════════════════════

-- ── 4a: Total revenue per payment method ───────────────────────────
SELECT
    dpm.name AS payment_method,
    SUM(ft.fare_amount) AS total_revenue
FROM fact_trips ft
JOIN dim_payment_method dpm ON ft.payment_method_key = dpm.payment_method_key
GROUP BY dpm.name
ORDER BY total_revenue DESC;


-- ── 4b: Average fare per trip, per payment method, per month ───────
SELECT
    dpm.name AS payment_method,
    dd.year,
    dd.month,
    ROUND(AVG(ft.fare_amount), 2) AS avg_fare_per_trip,
    COUNT(*) AS trip_count
FROM fact_trips ft
JOIN dim_payment_method dpm ON ft.payment_method_key = dpm.payment_method_key
JOIN dim_date dd            ON ft.date_key = dd.date_key
GROUP BY dpm.name, dd.year, dd.month
ORDER BY dpm.name, dd.year, dd.month;


-- ═══════════════════════════════════════════════════════════════════
-- TASK 5 — Busiest hour of day, with % of all trips (run against ride_dw)
-- ═══════════════════════════════════════════════════════════════════

-- Uses a window function SUM(COUNT(*)) OVER () to get the grand total
-- of all trips in the same query — no separate query needed.
--   COUNT(*)                  → trips in each hour (due to GROUP BY)
--   SUM(COUNT(*)) OVER ()     → total trips across ALL hours
--   empty OVER () = whole result set, no partitioning
SELECT
    dt.hour,
    COUNT(*) AS trip_count,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
    2) AS pct_of_all_trips
FROM fact_trips ft
JOIN dim_time dt ON ft.time_key = dt.time_key
GROUP BY dt.hour
ORDER BY dt.hour;