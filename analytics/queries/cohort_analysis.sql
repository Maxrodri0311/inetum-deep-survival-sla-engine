-- inetum_senior_data_scientist_bridge_project - Advanced Analytical SQL
-- Longitudinal Cohort & Time-to-Event Window Functions

WITH raw_events AS (
    SELECT
        inetum_senior_d_id AS entity_id,
        primary_metric,
        volume_count,
        is_active,
        status_category,
        ROW_NUMBER() OVER (
            PARTITION BY inetum_senior_d_id
            ORDER BY primary_metric ASC
        ) AS event_sequence,
        AVG(primary_metric) OVER (
            PARTITION BY status_category
        ) AS category_benchmark_avg
    FROM telemetry_events
),
cohort_matrix AS (
    SELECT
        entity_id,
        status_category,
        primary_metric,
        event_sequence,
        category_benchmark_avg,
        CASE
            WHEN primary_metric >= category_benchmark_avg * 1.25 THEN 'HIGH_RISK_SURGE'
            WHEN primary_metric <= category_benchmark_avg * 0.75 THEN 'STABLE_RETENTION'
            ELSE 'NOMINAL_VARIANCE'
        END AS risk_tier,
        DENSE_RANK() OVER (
            ORDER BY primary_metric DESC
        ) AS global_severity_rank
    FROM raw_events
)
SELECT
    risk_tier,
    COUNT(DISTINCT entity_id) AS total_entities,
    ROUND(AVG(primary_metric)::numeric, 2) AS avg_primary_metric,
    ROUND(AVG(volume_count)::numeric, 2) AS avg_volume_count,
    ROUND(AVG(category_benchmark_avg)::numeric, 2) AS benchmark_threshold
FROM cohort_matrix
GROUP BY risk_tier
ORDER BY total_entities DESC;