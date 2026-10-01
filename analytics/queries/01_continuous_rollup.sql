-- ==============================================================================
-- Inetum SLA Telemetry - Continuous Rollup & Materialized Aggregations
-- Target: PostgreSQL 16 Enterprise / Amazon RDS Aurora
-- Architecture: Materialized Views with Window Moving Averages & Hazard Ratios
-- ==============================================================================

SET search_path TO inetum_sla_lakehouse, public;

DROP MATERIALIZED VIEW IF EXISTS mv_sla_continuous_risk_rollup CASCADE;

CREATE MATERIALIZED VIEW mv_sla_continuous_risk_rollup AS
WITH telemetry_windowed AS (
    SELECT
        t.contract_id,
        m.client_tier,
        m.workload_type,
        t.ticket_severity,
        t.system_load_ratio,
        t.duration_hours,
        t.event_occurred,
        t.event_timestamp,
        DATE_TRUNC('day', t.event_timestamp) AS snapshot_date,
        -- Moving 7-day average MTTR per contract
        AVG(t.duration_hours) OVER (
            PARTITION BY t.contract_id 
            ORDER BY t.event_timestamp 
            RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
        ) AS rolling_7d_avg_duration,
        -- Cumulative event count per contract
        SUM(t.event_occurred) OVER (
            PARTITION BY t.contract_id 
            ORDER BY t.event_timestamp 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_breaches_to_date
    FROM sla_incident_telemetry t
    INNER JOIN sla_contracts_master m ON t.contract_id = m.contract_id
),
aggregated_workload_metrics AS (
    SELECT
        snapshot_date,
        client_tier,
        workload_type,
        COUNT(DISTINCT contract_id) AS active_contracts_count,
        COUNT(*) AS total_incidents_logged,
        SUM(event_occurred) AS total_sla_breaches,
        ROUND(AVG(system_load_ratio)::numeric, 3) AS avg_workload_load_ratio,
        ROUND(AVG(rolling_7d_avg_duration)::numeric, 2) AS avg_rolling_7d_duration_hours,
        ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_hours)::numeric, 2) AS p95_duration_hours,
        ROUND((SUM(event_occurred)::numeric / NULLIF(COUNT(*), 0) * 100)::numeric, 2) AS empirical_breach_rate_pct
    FROM telemetry_windowed
    GROUP BY snapshot_date, client_tier, workload_type
)
SELECT
    snapshot_date,
    client_tier,
    workload_type,
    active_contracts_count,
    total_incidents_logged,
    total_sla_breaches,
    avg_workload_load_ratio,
    avg_rolling_7d_duration_hours,
    p95_duration_hours,
    empirical_breach_rate_pct,
    -- Rank workloads by severity within tier
    DENSE_RANK() OVER (
        PARTITION BY snapshot_date, client_tier 
        ORDER BY empirical_breach_rate_pct DESC
    ) AS tier_workload_risk_rank,
    CURRENT_TIMESTAMP AS refreshed_at
FROM aggregated_workload_metrics
WITH DATA;

-- Unique Composite Index for Concurrent Materialized View Refresh
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_sla_risk_rollup_unique
    ON mv_sla_continuous_risk_rollup (snapshot_date, client_tier, workload_type);

-- Refresh Function
CREATE OR REPLACE FUNCTION refresh_sla_risk_rollup()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_sla_continuous_risk_rollup;
END;
$$ LANGUAGE plpgsql;