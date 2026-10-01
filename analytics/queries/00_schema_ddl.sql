-- ==============================================================================
-- Inetum Managed Cloud Services - SLA Telemetry & Survival Analytics DDL
-- Target: PostgreSQL 16 Enterprise / Amazon RDS Aurora
-- Architecture: Time-Series Range Partitioning, BRIN Indexing & Constraints
-- ==============================================================================

CREATE SCHEMA IF NOT EXISTS inetum_sla_lakehouse;
SET search_path TO inetum_sla_lakehouse, public;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Master Contracts Registry
CREATE TABLE IF NOT EXISTS sla_contracts_master (
    contract_id VARCHAR(64) PRIMARY KEY,
    client_tier VARCHAR(32) NOT NULL CHECK (client_tier IN ('Strategic Tier-1', 'Enterprise Tier-2', 'Standard Core')),
    workload_type VARCHAR(64) NOT NULL CHECK (workload_type IN ('Cloud Migration', 'Managed DevOps', 'AI Data Pipeline', 'SAP S/4HANA', 'Cybersecurity SOC')),
    contract_margin_pct NUMERIC(5, 2) NOT NULL DEFAULT 28.50,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Incident & Survival Telemetry: Range-Partitioned by Event Timestamp
CREATE TABLE IF NOT EXISTS sla_incident_telemetry (
    telemetry_id UUID DEFAULT uuid_generate_v4(),
    contract_id VARCHAR(64) NOT NULL REFERENCES sla_contracts_master(contract_id),
    ticket_severity INT NOT NULL CHECK (ticket_severity BETWEEN 1 AND 4),
    incident_volume_30d INT NOT NULL CHECK (incident_volume_30d >= 0),
    mttr_historical_hours NUMERIC(6, 2) NOT NULL CHECK (mttr_historical_hours > 0),
    engineer_on_call_exp_months INT NOT NULL CHECK (engineer_on_call_exp_months >= 0),
    system_load_ratio NUMERIC(5, 3) NOT NULL CHECK (system_load_ratio >= 0.0),
    duration_hours NUMERIC(8, 2) NOT NULL CHECK (duration_hours > 0),
    event_occurred INT NOT NULL CHECK (event_occurred IN (0, 1)),
    event_timestamp TIMESTAMPTZ NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_sla_incident_telemetry PRIMARY KEY (event_timestamp, telemetry_id)
) PARTITION BY RANGE (event_timestamp);

-- Time-Series Partitions (Quarterly Rolling Windows)
CREATE TABLE IF NOT EXISTS sla_incident_telemetry_2026_q1 PARTITION OF sla_incident_telemetry
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS sla_incident_telemetry_2026_q2 PARTITION OF sla_incident_telemetry
    FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS sla_incident_telemetry_2026_q3 PARTITION OF sla_incident_telemetry
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS sla_incident_telemetry_default PARTITION OF sla_incident_telemetry
    DEFAULT;

-- 3. Inference Results Store
CREATE TABLE IF NOT EXISTS sla_survival_inferences (
    inference_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_id VARCHAR(64) NOT NULL REFERENCES sla_contracts_master(contract_id),
    hazard_ratio NUMERIC(8, 4) NOT NULL,
    cumulative_hazard_30d NUMERIC(8, 4) NOT NULL,
    survival_prob_30d NUMERIC(5, 4) NOT NULL,
    survival_prob_60d NUMERIC(5, 4) NOT NULL,
    survival_prob_90d NUMERIC(5, 4) NOT NULL,
    risk_tier VARCHAR(32) NOT NULL,
    recommended_mitigation TEXT NOT NULL,
    evaluated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 4. High-Throughput Indexes
-- BRIN Index for 95% space reduction on append-only time series
CREATE INDEX IF NOT EXISTS idx_sla_telemetry_brin_timestamp 
    ON sla_incident_telemetry USING BRIN (event_timestamp) 
    WITH (pages_per_range = 32);

-- Composite B-Tree index for contract history queries
CREATE INDEX IF NOT EXISTS idx_sla_telemetry_contract_lookup 
    ON sla_incident_telemetry (contract_id, event_timestamp DESC);

-- Index for high-risk triage searches
CREATE INDEX IF NOT EXISTS idx_sla_inferences_risk_tier 
    ON sla_survival_inferences (risk_tier, evaluated_at DESC);