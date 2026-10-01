-- ==============================================================================
-- Inetum Managed Cloud Services - Longitudinal Kaplan-Meier Survival Life Tables
-- Target: PostgreSQL 16 Enterprise / Amazon RDS Aurora
-- Architecture: Non-Parametric Product-Limit Survival Estimator in Pure SQL,
--               Logarithmic Product Integration & Greenwood Asymptotic Variance
-- ==============================================================================

SET search_path TO inetum_sla_lakehouse, public;

WITH binned_telemetry AS (
    -- Map continuous incident duration into operational SLA evaluation intervals
    SELECT
        t.telemetry_id,
        t.contract_id,
        m.client_tier,
        t.duration_hours,
        t.event_occurred,
        CASE
            WHEN t.duration_hours <= 4.0 THEN 1
            WHEN t.duration_hours <= 12.0 THEN 2
            WHEN t.duration_hours <= 24.0 THEN 3
            WHEN t.duration_hours <= 48.0 THEN 4
            WHEN t.duration_hours <= 72.0 THEN 5
            WHEN t.duration_hours <= 168.0 THEN 6
            WHEN t.duration_hours <= 360.0 THEN 7
            ELSE 8
        END AS interval_idx,
        CASE
            WHEN t.duration_hours <= 4.0 THEN '[000 - 004h] Acute Rapid Triage'
            WHEN t.duration_hours <= 12.0 THEN '[004 - 012h] Extended Day Escalation'
            WHEN t.duration_hours <= 24.0 THEN '[012 - 024h] 24h Critical Boundary'
            WHEN t.duration_hours <= 48.0 THEN '[024 - 048h] 48h SLA Hard Threshold'
            WHEN t.duration_hours <= 72.0 THEN '[048 - 072h] 3-Day Chronic Latency'
            WHEN t.duration_hours <= 168.0 THEN '[072 - 168h] 1-Week Degradation'
            WHEN t.duration_hours <= 360.0 THEN '[168 - 360h] Fortnightly Stagnation'
            ELSE '[360 - 720h] Monthly Extreme Outlier'
        END AS interval_label,
        CASE
            WHEN t.duration_hours <= 4.0 THEN 4.0
            WHEN t.duration_hours <= 12.0 THEN 12.0
            WHEN t.duration_hours <= 24.0 THEN 24.0
            WHEN t.duration_hours <= 48.0 THEN 48.0
            WHEN t.duration_hours <= 72.0 THEN 72.0
            WHEN t.duration_hours <= 168.0 THEN 168.0
            WHEN t.duration_hours <= 360.0 THEN 360.0
            ELSE 720.0
        END AS interval_upper_bound_hours
    FROM sla_incident_telemetry t
    INNER JOIN sla_contracts_master m ON t.contract_id = m.contract_id
),
interval_frequencies AS (
    -- Aggregate observed breach events (d_k) and censored tickets (c_k) per stratum
    SELECT
        client_tier,
        interval_idx,
        interval_label,
        interval_upper_bound_hours,
        COUNT(*) AS total_incidents_in_interval,
        SUM(CASE WHEN event_occurred = 1 THEN 1 ELSE 0 END) AS breach_events_d_k,
        SUM(CASE WHEN event_occurred = 0 THEN 1 ELSE 0 END) AS censored_tickets_c_k
    FROM binned_telemetry
    GROUP BY client_tier, interval_idx, interval_label, interval_upper_bound_hours
),
cumulative_risk_sets AS (
    -- Compute dynamic size of cohort at risk (n_k) entering each discrete interval
    SELECT
        client_tier,
        interval_idx,
        interval_label,
        interval_upper_bound_hours,
        total_incidents_in_interval,
        breach_events_d_k,
        censored_tickets_c_k,
        -- Number entering interval = total cohort minus those who exited in preceding intervals
        SUM(total_incidents_in_interval) OVER (
            PARTITION BY client_tier
            ORDER BY interval_idx ASC
            ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
        ) AS cohort_at_risk_n_k
    FROM interval_frequencies
),
conditional_probabilities AS (
    -- Compute interval hazard rate q_k and interval survival probability p_k
    SELECT
        client_tier,
        interval_idx,
        interval_label,
        interval_upper_bound_hours,
        cohort_at_risk_n_k,
        breach_events_d_k,
        censored_tickets_c_k,
        -- Instantaneous interval hazard rate: q_k = d_k / n_k
        ROUND((breach_events_d_k::numeric / NULLIF(cohort_at_risk_n_k, 0))::numeric, 5) AS interval_hazard_rate,
        -- Conditional survival rate: p_k = 1 - (d_k / n_k)
        ROUND((1.0 - (breach_events_d_k::numeric / NULLIF(cohort_at_risk_n_k, 0)))::numeric, 5) AS interval_survival_prob,
        -- Greenwood variance summand: d_k / (n_k * (n_k - d_k))
        CASE 
            WHEN cohort_at_risk_n_k > breach_events_d_k AND breach_events_d_k > 0 THEN
                breach_events_d_k::numeric / (cohort_at_risk_n_k::numeric * (cohort_at_risk_n_k - breach_events_d_k)::numeric)
            ELSE 0.0
        END AS greenwood_variance_term
    FROM cumulative_risk_sets
),
kaplan_meier_integrator AS (
    -- Multiply conditional survival probabilities using logarithmic summation: S(t) = exp(sum(ln(p_k)))
    SELECT
        client_tier,
        interval_idx,
        interval_label,
        interval_upper_bound_hours,
        cohort_at_risk_n_k,
        breach_events_d_k,
        censored_tickets_c_k,
        interval_hazard_rate,
        interval_survival_prob,
        -- Cumulative survival estimate S_hat(t)
        EXP(SUM(LN(NULLIF(interval_survival_prob, 0.0))) OVER (
            PARTITION BY client_tier
            ORDER BY interval_idx ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )) AS km_survival_probability,
        -- Cumulative Greenwood variance sum
        SUM(greenwood_variance_term) OVER (
            PARTITION BY client_tier
            ORDER BY interval_idx ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_greenwood_variance_sum
    FROM conditional_probabilities
)
-- Produce Final Executive Life Table with 95% Greenwood Confidence Bounds
SELECT
    client_tier,
    interval_idx,
    interval_label,
    interval_upper_bound_hours AS threshold_hours,
    cohort_at_risk_n_k,
    breach_events_d_k,
    censored_tickets_c_k,
    interval_hazard_rate,
    -- Product-limit survival probability S(t)
    ROUND((km_survival_probability * 100.0)::numeric, 2) AS cumulative_survival_pct,
    -- True cumulative breach failure risk: F(t) = 1 - S(t)
    ROUND(((1.0 - km_survival_probability) * 100.0)::numeric, 2) AS cumulative_breach_hazard_pct,
    -- Greenwood Standard Error
    ROUND((km_survival_probability * SQRT(cumulative_greenwood_variance_sum) * 100.0)::numeric, 2) AS greenwood_std_error_pct,
    -- Lower 95% Confidence Limit
    ROUND((GREATEST(0.0, km_survival_probability - 1.96 * (km_survival_probability * SQRT(cumulative_greenwood_variance_sum))) * 100.0)::numeric, 2) AS ci_lower_95_pct,
    -- Upper 95% Confidence Limit
    ROUND((LEAST(1.0, km_survival_probability + 1.96 * (km_survival_probability * SQRT(cumulative_greenwood_variance_sum))) * 100.0)::numeric, 2) AS ci_upper_95_pct
FROM kaplan_meier_integrator
ORDER BY 
    client_tier ASC,
    interval_idx ASC;
