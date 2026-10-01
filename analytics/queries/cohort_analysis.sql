-- ==============================================================================
-- Inetum Managed Cloud Services - Longitudinal Cohort & SLA Degradation Analysis
-- Target: PostgreSQL 16 Enterprise / Amazon RDS Aurora
-- Architecture: Advanced Window Functions (NTILE, LAG, LEAD, FIRST_VALUE),
--               Longitudinal Drift Tracking & Contract Cohort Segmentation
-- ==============================================================================

SET search_path TO inetum_sla_lakehouse, public;

WITH contract_onboarding_cohorts AS (
    -- Identify the inception cohort month for each enterprise contract
    SELECT
        contract_id,
        client_tier,
        workload_type,
        contract_margin_pct,
        DATE_TRUNC('month', created_at) AS cohort_month
    FROM sla_contracts_master
),
sequenced_incident_history AS (
    -- Enrich telemetry with longitudinal window metrics per contract lifecycle
    SELECT
        t.telemetry_id,
        t.contract_id,
        c.client_tier,
        c.workload_type,
        c.cohort_month,
        t.ticket_severity,
        t.incident_volume_30d,
        t.system_load_ratio,
        t.duration_hours,
        t.event_occurred,
        t.event_timestamp,
        -- Sequence number of incident within contract relationship
        ROW_NUMBER() OVER (
            PARTITION BY t.contract_id 
            ORDER BY t.event_timestamp ASC
        ) AS incident_lifecycle_sequence,
        -- Prior incident duration (MTTR degradation velocity)
        LAG(t.duration_hours, 1) OVER (
            PARTITION BY t.contract_id 
            ORDER BY t.event_timestamp ASC
        ) AS prev_incident_duration_hours,
        -- Subsequent incident duration (Recovery acceleration indicator)
        LEAD(t.duration_hours, 1) OVER (
            PARTITION BY t.contract_id 
            ORDER BY t.event_timestamp ASC
        ) AS next_incident_duration_hours,
        -- Baseline incident duration recorded at initial contract onboarding
        FIRST_VALUE(t.duration_hours) OVER (
            PARTITION BY t.contract_id 
            ORDER BY t.event_timestamp ASC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS baseline_contract_duration_hours,
        -- Peer cohort benchmark average duration
        AVG(t.duration_hours) OVER (
            PARTITION BY c.client_tier, c.workload_type
        ) AS peer_cohort_avg_duration_hours,
        -- Hazard quartile segmentation across peer tier
        NTILE(4) OVER (
            PARTITION BY c.client_tier 
            ORDER BY t.duration_hours ASC
        ) AS duration_hazard_quartile
    FROM sla_incident_telemetry t
    INNER JOIN contract_onboarding_cohorts c ON t.contract_id = c.contract_id
),
longitudinal_hazard_scoring AS (
    -- Compute velocity metrics and acute volatility flags
    SELECT
        telemetry_id,
        contract_id,
        client_tier,
        workload_type,
        cohort_month,
        ticket_severity,
        duration_hours,
        event_occurred,
        incident_lifecycle_sequence,
        duration_hazard_quartile,
        baseline_contract_duration_hours,
        peer_cohort_avg_duration_hours,
        -- Absolute duration delta from baseline onboarding SLA
        ROUND((duration_hours - baseline_contract_duration_hours)::numeric, 2) AS duration_drift_from_baseline,
        -- Inter-incident velocity: percentage change in resolution time from previous ticket
        CASE 
            WHEN prev_incident_duration_hours IS NULL OR prev_incident_duration_hours = 0 THEN 0.0
            ELSE ROUND(((duration_hours - prev_incident_duration_hours) / prev_incident_duration_hours * 100.0)::numeric, 2)
        END AS mttr_velocity_pct_change,
        -- Structural hazard categorization based on quartiles and load
        CASE
            WHEN duration_hazard_quartile = 4 AND system_load_ratio >= 1.25 THEN 'CRITICAL_CONGESTION_STAGNATION'
            WHEN duration_hazard_quartile = 4 THEN 'CHRONIC_LATENCY_OUTLIER'
            WHEN duration_hazard_quartile IN (2, 3) THEN 'NOMINAL_OPERATIONAL_RANGE'
            ELSE 'HIGH_EFFICIENCY_RESOLVED'
        END AS longitudinal_hazard_tier
    FROM sequenced_incident_history
)
-- Aggregate Cohort Performance Matrix for Executive Leadership
SELECT
    TO_CHAR(cohort_month, 'YYYY-MM') AS onboarding_cohort,
    client_tier,
    workload_type,
    longitudinal_hazard_tier,
    COUNT(DISTINCT contract_id) AS total_contracts_in_cohort,
    COUNT(*) AS total_incidents_recorded,
    SUM(event_occurred) AS total_sla_breach_events,
    ROUND((SUM(event_occurred)::numeric / NULLIF(COUNT(*), 0) * 100.0)::numeric, 2) AS cohort_breach_rate_pct,
    ROUND(AVG(duration_hours)::numeric, 2) AS avg_duration_hours,
    ROUND(AVG(duration_drift_from_baseline)::numeric, 2) AS avg_drift_from_onboarding_hours,
    ROUND(AVG(mttr_velocity_pct_change)::numeric, 2) AS avg_mttr_acceleration_pct,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration_hours)::numeric, 2) AS median_duration_hours,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_hours)::numeric, 2) AS p95_duration_hours
FROM longitudinal_hazard_scoring
GROUP BY 
    cohort_month,
    client_tier,
    workload_type,
    longitudinal_hazard_tier
HAVING COUNT(*) >= 5
ORDER BY 
    cohort_month DESC,
    client_tier ASC,
    cohort_breach_rate_pct DESC;