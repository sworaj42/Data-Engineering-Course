-- week3_reliability.sql
-- Week 3 Assignment
-- Submit TWO files:
--   1. week3_reliability.sql  (this file — SQL tasks)
--   2. transactional_loader.py (Python task — Q5)
--
-- All SQL runs against the normalized schema from Week 2
-- (drivers, riders, locations, trips)

-- ─────────────────────────────────────────────────────────────────
-- Q1: Add indexes to the trips table
--
-- Before adding ANY index, run EXPLAIN ANALYZE on each query below
-- and record the execution time in a comment.
-- Then add your indexes and run EXPLAIN ANALYZE again.
-- The comparison IS the answer — not just the CREATE INDEX statement.
-- ─────────────────────────────────────────────────────────────────

-- Baseline queries — run EXPLAIN ANALYZE on each BEFORE indexing:

-- Query A: filter by driver
EXPLAIN ANALYZE
SELECT * FROM trips WHERE driver_id = 3;
-- Query A before: Seq Scan, execution time = 212.009 ms

-- Query B: filter by passenger
EXPLAIN ANALYZE
SELECT * FROM trips WHERE passenger_id = 5;
-- Query B before: Parallel Seq Scan, execution time = 109.375 ms

-- Query C: filter by requested_at (common in pipelines for date ranges)
EXPLAIN ANALYZE
SELECT * FROM trips WHERE requested_at > '2024-01-01';
-- Query C before: Seq Scan, execution time = 182.155 ms

-- YOUR INDEXES HERE:

-- Index 1: driver_id — most frequently queried column (driver trip history)
-- High cardinality: many unique driver IDs → index is very effective
CREATE INDEX idx_trips_driver_id ON trips(driver_id);

-- Index 2: passenger_id — queried every time a passenger views ride history
-- High cardinality: many unique passenger IDs → index is very effective
CREATE INDEX idx_trips_passenger_id ON trips(passenger_id);

-- Index 3: requested_at — used for date range filters and ORDER BY in pipelines
-- High cardinality: timestamps are nearly unique → good index candidate
CREATE INDEX idx_trips_requested_at ON trips(requested_at);

-- Record results after indexing:
-- Query A after: Bitmap Index Scan on idx_trips_driver_id, execution time = 41.388 ms  (5x faster)
-- Query B after: Bitmap Index Scan on idx_trips_passenger_id, execution time = 24.164 ms (4.5x faster)
-- Query C after: Seq Scan still chosen, execution time = 88.098 ms
--   → PostgreSQL ignored the index because 63% of rows matched the filter.
--   → Indexes help most when filtering to a small percentage of rows (low selectivity).
--   → This is expected behaviour, not a mistake.


-- ─────────────────────────────────────────────────────────────────
-- Q2: Create completed_trips_view
--
-- Must return only completed trips with ALL of these columns:
--   trip_id, driver_name, rider_name,
--   pickup_city, dropoff_city,
--   fare_amount, distance_km, rating,
--   payment_method, requested_at, completed_at
--
-- No IDs in the output — use JOINs to resolve all foreign keys.
-- 5 tables joined: trips, drivers, passengers, locations (x2), payment_methods
-- WHERE t.status = 'completed' filters inside the view definition
-- so every SELECT from this view always returns only completed trips.
-- ─────────────────────────────────────────────────────────────────

CREATE VIEW completed_trips_view AS
SELECT
    t.trip_id,
    d.name                  AS driver_name,
    p.name                  AS rider_name,
    pick.city_name          AS pickup_city,
    drop_.city_name         AS dropoff_city,
    t.fare_amount,
    t.distance_km,
    t.rating,
    pm.name                 AS payment_method,
    t.requested_at,
    t.completed_at
FROM trips t
JOIN drivers d          ON t.driver_id           = d.driver_id
JOIN passengers p       ON t.passenger_id        = p.passenger_id
JOIN locations pick     ON t.pickup_location_id  = pick.location_id
JOIN locations drop_    ON t.dropoff_location_id = drop_.location_id
JOIN payment_methods pm ON t.payment_method_id   = pm.payment_method_id
WHERE t.status = 'completed';

-- Verify:
SELECT * FROM completed_trips_view LIMIT 5;
SELECT COUNT(*) FROM completed_trips_view;
-- Expected count: ~599,768 (completed trips from 1M row dataset)


-- ─────────────────────────────────────────────────────────────────
-- Q3: driver_summary view
--
-- One row per driver showing:
--   driver_name, total_trips, completed_trips, cancelled_trips,
--   cancellation_rate %, avg_fare, avg_rating
--
-- Key decisions:
-- 1. COUNT(*) FILTER is used instead of CASE WHEN — cleaner and more readable.
--    FILTER applies a condition to an aggregate without needing a subquery.
--    e.g. COUNT(trip_id) FILTER (WHERE status = 'completed') counts only completed rows.
--
-- 2. NULLIF(COUNT(t.trip_id), 0) prevents division by zero for drivers with no trips.
--    If a driver has 0 trips, NULLIF returns NULL instead of 0, making the rate NULL
--    rather than throwing a division by zero error.
--
-- 3. LEFT JOIN ensures drivers with no trips still appear in the summary with 0s.
--    An INNER JOIN would exclude them entirely.
-- ─────────────────────────────────────────────────────────────────

CREATE VIEW driver_summary AS
SELECT
    d.name                                                          AS driver_name,
    COUNT(t.trip_id)                                                AS total_trips,
    COUNT(t.trip_id) FILTER (WHERE t.status = 'completed')         AS completed_trips,
    COUNT(t.trip_id) FILTER (WHERE t.status = 'cancelled')         AS cancelled_trips,
    ROUND(
        COUNT(t.trip_id) FILTER (WHERE t.status = 'cancelled')
        * 100.00 / NULLIF(COUNT(t.trip_id), 0), 2
    )                                                               AS cancellation_rate,
    ROUND(AVG(t.fare_amount), 2)                                    AS avg_fare,
    ROUND(AVG(t.rating), 2)                                         AS avg_rating
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
GROUP BY d.name;

-- Verify:
SELECT * FROM driver_summary ORDER BY total_trips DESC;
-- Expected: 11 rows, one per driver
-- cancellation_rate should be ~20% for most drivers
-- avg_rating should be ~3.00

-- ─────────────────────────────────────────────────────────────────
-- Q4: Transaction with intentional failure
--
-- Write a transaction that:
--   1. Inserts a new driver named 'Test Driver'
--   2. Inserts 3 valid trips for that driver
--   3. Inserts a 4th trip with rating = 99 (violates CHECK constraint)
--
-- The entire transaction should roll back.
-- Verify with: SELECT * FROM drivers WHERE name = 'Test Driver';
-- Expected: 0 rows (atomicity — nothing committed)
-- ─────────────────────────────────────────────────────────────────

-- YOUR TRANSACTION HERE:

BEGIN;

-- Step 1: Insert new driver
INSERT INTO drivers (name) VALUES ('Test Driver');

-- Step 2: Insert 3 valid trips for that driver
INSERT INTO trips (
    driver_id, passenger_id,
    pickup_location_id, dropoff_location_id,
    fare_amount, distance_km, status,
    requested_at, rating, payment_method_id
)
VALUES
    ((SELECT driver_id FROM drivers WHERE name = 'Test Driver'), 1, 1, 2, 500.00, 10.5, 'completed', '2024-06-01 10:00:00', 4.5, 1),
    ((SELECT driver_id FROM drivers WHERE name = 'Test Driver'), 2, 2, 3, 300.00, 7.2,  'completed', '2024-06-02 11:00:00', 4.0, 1),
    ((SELECT driver_id FROM drivers WHERE name = 'Test Driver'), 3, 3, 4, 450.00, 9.0,  'completed', '2024-06-03 12:00:00', 3.5, 1);

-- Step 3: Insert 4th trip with rating = 99 — violates CHECK constraint
-- rating column is NUMERIC(2,1): max allowed value is 9.9
-- This causes numeric field overflow → entire transaction rolls back
-- proving atomicity: all or nothing, no partial commits
INSERT INTO trips (
    driver_id, passenger_id,
    pickup_location_id, dropoff_location_id,
    fare_amount, distance_km, status,
    requested_at, rating, payment_method_id
)
VALUES (
    (SELECT driver_id FROM drivers WHERE name = 'Test Driver'),
    4, 1, 3, 200.00, 5.0, 'completed',
    '2024-06-04 09:00:00', 99, 1
);

COMMIT;

-- Verification query:
SELECT
    'drivers' AS tbl,
    COUNT(*) AS test_driver_rows
FROM drivers
WHERE name = 'Test Driver'
UNION ALL
SELECT 'trips', COUNT(*)
FROM trips t
JOIN drivers d ON t.driver_id = d.driver_id
WHERE d.name = 'Test Driver';
-- Expected: 0 / 0


-- ─────────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────
-- Q6 (STRETCH): Window function — running total fare per driver
--
-- For each completed trip, show:
--   trip_id, driver_name, requested_at, fare_amount,
--   running_total_fare (driver's cumulative fare up to this trip)
--
-- Use: SUM(fare_amount) OVER (PARTITION BY driver_id ORDER BY requested_at)
-- Order the final output by driver_name, requested_at
--
-- How window functions work:
--   PARTITION BY driver_id → each driver gets their own running total
--                            resets to 0 for each new driver
--   ORDER BY requested_at  → accumulates fare chronologically trip by trip
--   SUM() OVER()           → unlike GROUP BY which collapses rows,
--                            OVER() keeps every row and adds a new column
--
-- Example output for Anita Rai:
--   trip 1: fare=1851.39  running_total=1851.39
--   trip 2: fare=1935.70  running_total=3787.09
--   trip 3: fare=1551.61  running_total=5338.70  ← accumulating over time
-- ─────────────────────────────────────────────────────────────────

-- YOUR QUERY HERE:

SELECT
    t.trip_id,
    d.name                                          AS driver_name,
    t.requested_at,
    t.fare_amount,
    SUM(t.fare_amount) OVER (
        PARTITION BY t.driver_id                    -- reset running total per driver
        ORDER BY t.requested_at                     -- accumulate in time order
    )                                               AS running_total_fare
FROM trips t
JOIN drivers d ON t.driver_id = d.driver_id
WHERE t.status = 'completed'
ORDER BY driver_name, t.requested_at;