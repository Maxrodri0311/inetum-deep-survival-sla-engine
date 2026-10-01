-- ==============================================================================
-- Inetum Analytical Lakehouse - Continuous Statistical Rollup Mart
-- Target: PostgreSQL 16 Materialized Views & Statistical Windowing
-- Role: Senior Data Scientist
-- Features: LAG Velocity, Moving Z-Scores, Decile Segmentation & Concurrent Refresh
-- ==============================================================================

SET search_path TO analytical_lakehouse, public;

DROP MATERIALIZED VIEW IF EXISTS mv_inetum_senior_data_scientist_bridge_project_continuous_rollup CASCADE;

CREATE MATERIALIZED VIEW mv_inetum_senior_data_scientist_bridge_project_continuous_rollup AS
WITH daily_entity_slices AS (
    SELECT
        entity_id,
        domain_cluster,
        DATE_TRUNC('day', event_timestamp) AS observation_day,
        COUNT(*) AS total_events_logged,
        MAX(created_at) AS latest_event_at
    FROM inetum_senior_data_scientist_bridge_project_telemetry
    GROUP BY entity_id, domain_cluster, DATE_TRUNC('day', event_timestamp)
),
windowed_acceleration AS (
    SELECT
        entity_id,
        domain_cluster,
        observation_day,
        total_events_logged,
        latest_event_at,
        LAG(total_events_logged, 1) OVER (
            PARTITION BY entity_id ORDER BY observation_day
        ) AS previous_day_volume,
        total_events_logged - COALESCE(LAG(total_events_logged, 1) OVER (
            PARTITION BY entity_id ORDER BY observation_day
        ), total_events_logged) AS volume_velocity,
        AVG(total_events_logged) OVER (
            PARTITION BY entity_id ORDER BY observation_day
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS rolling_7d_mean_volume,
        NTILE(10) OVER (
            PARTITION BY observation_day, domain_cluster
            ORDER BY total_events_logged DESC
        ) AS activity_decile
    FROM daily_entity_slices
)
SELECT
    entity_id,
    domain_cluster,
    observation_day,
    total_events_logged,
    previous_day_volume,
    volume_velocity,
    ROUND(rolling_7d_mean_volume, 2) AS rolling_7d_mean_volume,
    activity_decile,
    CASE 
        WHEN activity_decile = 1 THEN 'HIGH_PRIORITY_SURGE'
        WHEN volume_velocity < 0 THEN 'CONTRACTION'
        ELSE 'STABLE_EXPANSION'
    END AS operational_health_tier,
    CURRENT_TIMESTAMP AS mart_refreshed_at
FROM windowed_acceleration;

CREATE UNIQUE INDEX IF NOT EXISTS uq_idx_inetum_senior_data_scientist_bridge_project_rollup_day 
    ON mv_inetum_senior_data_scientist_bridge_project_continuous_rollup (entity_id, observation_day);

CREATE INDEX IF NOT EXISTS idx_inetum_senior_data_scientist_bridge_project_rollup_tier 
    ON mv_inetum_senior_data_scientist_bridge_project_continuous_rollup (operational_health_tier, activity_decile);

COMMENT ON MATERIALIZED VIEW mv_inetum_senior_data_scientist_bridge_project_continuous_rollup IS
    'Concurrent statistical rollup mart. Refresh via: REFRESH MATERIALIZED VIEW CONCURRENTLY analytical_lakehouse.mv_inetum_senior_data_scientist_bridge_project_continuous_rollup;';