-- ==============================================================================
-- Inetum SLA Telemetry - Real-Time Autonomous Escalation Triggers
-- Target: PostgreSQL 16 Enterprise / Amazon RDS Aurora
-- Architecture: PL/pgSQL Event Functions, Audit Tables & Dynamic Hazard Triggers
-- ==============================================================================

SET search_path TO inetum_sla_lakehouse, public;

-- Escalation Audit Table
CREATE TABLE IF NOT EXISTS sla_escalation_audit_log (
    escalation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_id VARCHAR(64) NOT NULL,
    triggering_severity INT NOT NULL,
    system_load_ratio NUMERIC(5, 3) NOT NULL,
    escalation_level VARCHAR(32) NOT NULL,
    notification_payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sla_escalation_contract_created
    ON sla_escalation_audit_log (contract_id, created_at DESC);

-- Trigger Function: Real-Time Breach Hazard Detection
CREATE OR REPLACE FUNCTION fn_detect_sla_breach_hazard()
RETURNS TRIGGER AS $$
DECLARE
    v_client_tier VARCHAR(32);
    v_workload_type VARCHAR(64);
    v_escalation_level VARCHAR(32);
BEGIN
    -- Retrieve contract business tier
    SELECT client_tier, workload_type 
    INTO v_client_tier, v_workload_type
    FROM sla_contracts_master
    WHERE contract_id = NEW.contract_id;

    -- Trigger condition: High system congestion (>1.35) or Outage severity (<=2)
    IF (NEW.system_load_ratio >= 1.35 AND NEW.ticket_severity <= 2) OR 
       (v_client_tier = 'Strategic Tier-1' AND NEW.system_load_ratio >= 1.20) THEN

        IF NEW.ticket_severity = 1 THEN
            v_escalation_level := 'TIER_1_EXECUTIVE_PAGER';
        ELSE
            v_escalation_level := 'TIER_2_STANDBY_STANDUP';
        END IF;

        INSERT INTO sla_escalation_audit_log (
            contract_id,
            triggering_severity,
            system_load_ratio,
            escalation_level,
            notification_payload
        ) VALUES (
            NEW.contract_id,
            NEW.ticket_severity,
            NEW.system_load_ratio,
            v_escalation_level,
            jsonb_build_object(
                'contract_id', NEW.contract_id,
                'client_tier', v_client_tier,
                'workload_type', v_workload_type,
                'duration_hours', NEW.duration_hours,
                'mttr_history', NEW.mttr_historical_hours,
                'timestamp', NEW.event_timestamp,
                'reason', 'Autonomous hazard detection triggered by DeepSurv SLA thresholds'
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Bind Trigger to SLA Incident Telemetry Table
DROP TRIGGER IF EXISTS trg_sla_hazard_escalation ON sla_incident_telemetry;

CREATE TRIGGER trg_sla_hazard_escalation
    AFTER INSERT OR UPDATE ON sla_incident_telemetry
    FOR EACH ROW
    EXECUTE FUNCTION fn_detect_sla_breach_hazard();