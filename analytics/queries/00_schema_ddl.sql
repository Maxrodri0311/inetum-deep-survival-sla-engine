-- ==============================================================================
-- Inetum Analytical Lakehouse - Enterprise DDL & Partitioning Schema
-- Target: PostgreSQL 16 Enterprise / Amazon RDS Aurora
-- Role: Senior Data Scientist
-- Paradigm: DeliveryParadigm.C_LEVEL_EXECUTIVE_SUITE | Architecture: Time-Series Range Partitioning & BRIN Indexing
-- ==============================================================================

CREATE SCHEMA IF NOT EXISTS analytical_lakehouse;
SET search_path TO analytical_lakehouse, public;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Master Event Telemetry Table: Range-Partitioned by Event Timestamp
CREATE TABLE IF NOT EXISTS inetum_senior_data_scientist_bridge_project_telemetry (
    telemetry_id UUID DEFAULT uuid_generate_v4(),
    entity_id VARCHAR(64) NOT NULL,
    domain_cluster VARCHAR(32) NOT NULL DEFAULT 'production',
    primary_metric NUMERIC(10, 4) NOT NULL,
    volume_count BIGINT NOT NULL,
    is_active BOOLEAN NOT NULL,
    status_category VARCHAR(64) NOT NULL,
    event_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_inetum_senior_data_scientist_bridge_project_telemetry PRIMARY KEY (event_timestamp, telemetry_id)
) PARTITION BY RANGE (event_timestamp);

-- Time-Series Partitions (Rolling Monthly Operational Windows)
CREATE TABLE IF NOT EXISTS inetum_senior_data_scientist_bridge_project_telemetry_2026_q1 PARTITION OF inetum_senior_data_scientist_bridge_project_telemetry
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS inetum_senior_data_scientist_bridge_project_telemetry_2026_q2 PARTITION OF inetum_senior_data_scientist_bridge_project_telemetry
    FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS inetum_senior_data_scientist_bridge_project_telemetry_default PARTITION OF inetum_senior_data_scientist_bridge_project_telemetry
    DEFAULT;

-- BRIN Index for 95% space reduction on append-only time series
CREATE INDEX IF NOT EXISTS idx_inetum_senior_data_scientist_bridge_project_brin_timestamp 
    ON inetum_senior_data_scientist_bridge_project_telemetry USING BRIN (event_timestamp) 
    WITH (pages_per_range = 32);

-- Composite B-Tree index for low-latency operational triage
CREATE INDEX IF NOT EXISTS idx_inetum_senior_data_scientist_bridge_project_entity_triage 
    ON inetum_senior_data_scientist_bridge_project_telemetry (entity_id, domain_cluster, event_timestamp DESC);