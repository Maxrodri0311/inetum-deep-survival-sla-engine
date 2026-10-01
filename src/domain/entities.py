"""
src/domain/entities.py - Pure domain models for inetum-deep-survival-sla-engine.
Strict Pydantic v2 schema representing SLA Incident, Duration, and Survival Predictions.
Zero external I/O or vendor dependencies imported here.
"""

from enum import Enum
from typing import Annotated, Dict, List, Optional
from pydantic import BaseModel, ConfigDict, Field


class WorkloadType(str, Enum):
    CLOUD_MIGRATION = "Cloud Migration"
    MANAGED_DEVOPS = "Managed DevOps"
    AI_DATA_PIPELINE = "AI Data Pipeline"
    SAP_S4HANA = "SAP S/4HANA"
    CYBERSECURITY_SOC = "Cybersecurity SOC"


class ClientTier(str, Enum):
    STRATEGIC = "Strategic Tier-1"
    ENTERPRISE = "Enterprise Tier-2"
    STANDARD = "Standard Core"


class RiskTier(str, Enum):
    CRITICAL = "CRITICAL_SLA_BREACH_RISK"
    ELEVATED = "ELEVATED_MONITORING"
    NOMINAL = "NOMINAL_STABLE"


class SLAIncidentRecord(BaseModel):
    """Core domain entity representing managed service contracts and SLA incident tracking."""
    model_config = ConfigDict(strict=True, frozen=True)

    contract_id: str = Field(description="Unique contract identifier")
    client_tier: ClientTier = Field(description="Client SLA tier")
    workload_type: WorkloadType = Field(description="Consulting workload specialization")
    ticket_severity: int = Field(ge=1, le=4, description="Severity 1 (outage) to 4 (minor)")
    incident_volume_30d: int = Field(ge=0, description="Rolling 30-day incident frequency")
    mttr_historical_hours: float = Field(gt=0.0, description="Historical Mean Time To Resolution in hours")
    engineer_on_call_exp_months: int = Field(ge=0, description="Experience level of assigned engineer")
    system_load_ratio: float = Field(ge=0.0, le=2.0, description="Current CPU/Memory pressure ratio (1.0 = 100%)")
    contract_margin_pct: float = Field(ge=-50.0, le=100.0, description="Contract margin percentage")
    
    # Survival specific time-to-event dimensions
    duration_hours: float = Field(gt=0.0, description="Time to resolution or censorship window (T)")
    event_occurred: int = Field(ge=0, le=1, description="Censorship flag E: 1 = SLA Breach, 0 = Right-censored/Resolved on time")


class SurvivalInferenceResult(BaseModel):
    """Inference output from the DeepSurv / Proportional Hazards Engine."""
    model_config = ConfigDict(strict=True, frozen=True)

    contract_id: str
    hazard_ratio: float = Field(description="Relative risk exp(h(x)) relative to baseline")
    cumulative_hazard_30d: float = Field(ge=0.0, description="Integrated hazard H(30d)")
    survival_prob_30d: float = Field(ge=0.0, le=1.0, description="Probability S(30d) of maintaining SLA")
    survival_prob_60d: float = Field(ge=0.0, le=1.0, description="Probability S(60d) of maintaining SLA")
    survival_prob_90d: float = Field(ge=0.0, le=1.0, description="Probability S(90d) of maintaining SLA")
    risk_tier: RiskTier
    recommended_mitigation: str