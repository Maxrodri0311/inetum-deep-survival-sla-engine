-- ==============================================================================
-- Inetum Managed Cloud Services - Markov State-Transition Risk Migration Matrix
-- Target: PostgreSQL 16 Enterprise / Amazon RDS Aurora
-- Architecture: Discrete-Time Markov Chain (DTMC) Transition Probabilities,
--               Longitudinal Risk State Migration & Absorbing State Identification
-- ==============================================================================

SET search_path TO inetum_sla_lakehouse, public;

WITH ordered_inferences AS (
    -- Sequence successive risk assessments per contract
    SELECT
        inference_id,
        contract_id,
        hazard_ratio,
        cumulative_hazard_30d,
        survival_prob_30d,
        risk_tier AS current_state,
        evaluated_at,
        -- Next sequential risk state evaluated for the contract
        LEAD(risk_tier, 1) OVER (
            PARTITION BY contract_id 
            ORDER BY evaluated_at ASC
        ) AS next_state,
        -- Time delta to next inference assessment
        EXTRACT(EPOCH FROM (
            LEAD(evaluated_at, 1) OVER (
                PARTITION BY contract_id 
                ORDER BY evaluated_at ASC
            ) - evaluated_at
        )) / 3600.0 AS hours_to_next_assessment,
        -- Sequence counter for assessment cycle
        ROW_NUMBER() OVER (
            PARTITION BY contract_id 
            ORDER BY evaluated_at ASC
        ) AS assessment_sequence_id
    FROM sla_survival_inferences
),
filtered_transitions AS (
    -- Eliminate open-ended boundary assessments (final state with no forward transition)
    SELECT
        contract_id,
        current_state,
        next_state,
        hours_to_next_assessment,
        cumulative_hazard_30d
    FROM ordered_inferences
    WHERE next_state IS NOT NULL
),
transition_tallies AS (
    -- Compute pairwise state transition frequency N_ij and initial state volume N_i
    SELECT
        current_state,
        next_state,
        COUNT(*) AS transition_count,
        ROUND(AVG(hours_to_next_assessment)::numeric, 2) AS avg_holding_time_hours,
        ROUND(AVG(cumulative_hazard_30d)::numeric, 4) AS avg_cumulative_hazard_at_transition,
        -- Total departures from current_state: N_i
        SUM(COUNT(*)) OVER (
            PARTITION BY current_state
        ) AS total_departures_from_state
    FROM filtered_transitions
    GROUP BY current_state, next_state
),
markov_probability_matrix AS (
    -- Calculate empirical transition probabilities: P_ij = N_ij / N_i
    SELECT
        current_state,
        next_state,
        transition_count,
        total_departures_from_state,
        avg_holding_time_hours,
        avg_cumulative_hazard_at_transition,
        ROUND((transition_count::numeric / total_departures_from_state * 100.0)::numeric, 2) AS transition_probability_pct,
        -- Rank transition paths by statistical prevalence
        DENSE_RANK() OVER (
            PARTITION BY current_state 
            ORDER BY transition_count DESC
        ) AS transition_prominence_rank
    FROM transition_tallies
)
-- Display Formatted Markov Transition Matrix with Dynamic Pivot Columns
SELECT
    current_state AS origin_hazard_state,
    total_departures_from_state,
    -- Pivot probability columns across discrete hazard states
    MAX(CASE WHEN next_state = 'LOW_HAZARD' THEN transition_probability_pct ELSE 0.00 END) AS prob_to_low_pct,
    MAX(CASE WHEN next_state = 'MODERATE_HAZARD' THEN transition_probability_pct ELSE 0.00 END) AS prob_to_moderate_pct,
    MAX(CASE WHEN next_state = 'HIGH_HAZARD' THEN transition_probability_pct ELSE 0.00 END) AS prob_to_high_pct,
    MAX(CASE WHEN next_state = 'CRITICAL_HAZARD' THEN transition_probability_pct ELSE 0.00 END) AS prob_to_critical_pct,
    -- Holding time in origin state prior to migration
    ROUND(AVG(avg_holding_time_hours)::numeric, 1) AS mean_holding_time_hours,
    -- Acute deterioration flag: probability of direct jump to Critical >= 15%
    CASE 
        WHEN MAX(CASE WHEN next_state = 'CRITICAL_HAZARD' THEN transition_probability_pct ELSE 0.00 END) >= 15.00 
        THEN 'ACUTE_COLLAPSE_VULNERABILITY'
        WHEN MAX(CASE WHEN next_state = 'LOW_HAZARD' THEN transition_probability_pct ELSE 0.00 END) >= 50.00 
        THEN 'RESILIENT_CONVERGENCE'
        ELSE 'STOCHASTIC_EQUILIBRIUM'
    END AS state_stability_profile
FROM markov_probability_matrix
GROUP BY current_state, total_departures_from_state
ORDER BY 
    CASE current_state
        WHEN 'LOW_HAZARD' THEN 1
        WHEN 'MODERATE_HAZARD' THEN 2
        WHEN 'HIGH_HAZARD' THEN 3
        WHEN 'CRITICAL_HAZARD' THEN 4
        ELSE 5
    END ASC;
