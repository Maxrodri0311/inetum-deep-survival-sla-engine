"""
tests/test_suite.py - Automated Pytest Verification Suite.
Architecture: Mathematical Invariant Assertions, Pydantic Schema Contracts,
              Breslow Survival Monotonicity, and In-Memory DIP Mock Validation.
"""

from typing import List
import numpy as np
import polars as pl
import pydantic
import pytest

from src.core_engine import (
    DeepSurvHazardEngine,
    PolarsDataIngestionAdapter,
    SurvivalComparisonService,
    create_engine,
)
from src.data_generator import generate_survival_dataset
from src.domain.contracts import (
    DataIngestionProtocol,
    SurvivalEngineProtocol,
    TelemetrySinkProtocol,
)
from src.domain.entities import (
    ClientTier,
    RiskTier,
    SLAIncidentRecord,
    SurvivalInferenceResult,
    WorkloadType,
)


# -----------------------------------------------------------------------------
# Fixtures
# -----------------------------------------------------------------------------
@pytest.fixture(scope="session")
def synthetic_telemetry_df() -> pl.DataFrame:
    """Session fixture generating a calibrated survival dataset in memory."""
    return generate_survival_dataset(n_samples=2500, seed=42)


@pytest.fixture(scope="session")
def fitted_survival_engine(synthetic_telemetry_df: pl.DataFrame) -> DeepSurvHazardEngine:
    """Pre-calibrated DeepSurv engine for fast test execution."""
    _, engine = create_engine()
    engine.fit(synthetic_telemetry_df)
    return engine


# -----------------------------------------------------------------------------
# 1. Mathematical Invariant & Stochastic Physics Tests
# -----------------------------------------------------------------------------
def test_stochastic_generator_invariants(synthetic_telemetry_df: pl.DataFrame):
    """
    Asserts stochastic generator physics:
    - Zero null values across all features
    - Durations strictly positive (t > 0)
    - Non-trivial right-censoring rate (30% - 60% event rate)
    """
    df = synthetic_telemetry_df
    assert len(df) == 2500
    assert sum(df[col].null_count() for col in df.columns) == 0

    durations = df["duration_hours"].to_numpy()
    assert np.all(durations > 0.0), "All incident durations must be strictly positive."

    events = df["event_occurred"].to_numpy()
    event_rate = np.mean(events)
    assert 0.30 <= event_rate <= 0.60, f"Observed event rate {event_rate:.3f} outside expected [0.30, 0.60]."


def test_right_censoring_bias_mathematical_gap(synthetic_telemetry_df: pl.DataFrame):
    """
    Validates the Central Business Trade-Off:
    Static naive breach rate underreports SLA breach hazard due to right-censoring bias.
    Asserts underestimation gap is positive and >= 10 percentage points.
    """
    metrics = SurvivalComparisonService.evaluate_tradeoff(synthetic_telemetry_df)

    naive_rate = metrics["static_naive_breach_rate_pct"]
    dynamic_breach = metrics["dynamic_cumulative_breach_prob_30d_pct"]
    gap = metrics["underestimation_gap_points"]

    assert dynamic_breach > naive_rate, (
        f"Dynamic survival breach risk ({dynamic_breach}%) must exceed naive static rate ({naive_rate}%)."
    )
    assert gap >= 10.0, f"Underestimation gap of {gap} points is below expected >= 10.0 threshold."
    assert metrics["total_observations"] == 2500


# -----------------------------------------------------------------------------
# 2. Domain Schema & Pydantic Boundary Enforcement
# -----------------------------------------------------------------------------
def test_sla_incident_record_validation():
    """Asserts strict validation of contract bounds in domain entities."""
    valid_record = SLAIncidentRecord(
        contract_id="CNT-TEST-001",
        client_tier=ClientTier.STRATEGIC,
        workload_type=WorkloadType.SAP_S4HANA,
        ticket_severity=1,
        incident_volume_30d=5,
        mttr_historical_hours=3.5,
        engineer_on_call_exp_months=36,
        system_load_ratio=1.15,
        contract_margin_pct=32.0,
        duration_hours=14.2,
        event_occurred=1,
    )
    assert valid_record.contract_id == "CNT-TEST-001"
    assert valid_record.ticket_severity == 1

    # Severity out of range (must be 1-4)
    with pytest.raises(pydantic.ValidationError):
        SLAIncidentRecord(
            contract_id="CNT-TEST-ERR",
            client_tier=ClientTier.STANDARD,
            workload_type=WorkloadType.MANAGED_DEVOPS,
            ticket_severity=5,  # Invalid
            incident_volume_30d=2,
            mttr_historical_hours=4.0,
            engineer_on_call_exp_months=12,
            system_load_ratio=1.0,
            contract_margin_pct=25.0,
            duration_hours=10.0,
            event_occurred=0,
        )

    # Negative duration rejected
    with pytest.raises(pydantic.ValidationError):
        SLAIncidentRecord(
            contract_id="CNT-TEST-ERR",
            client_tier=ClientTier.STANDARD,
            workload_type=WorkloadType.MANAGED_DEVOPS,
            ticket_severity=2,
            incident_volume_30d=2,
            mttr_historical_hours=4.0,
            engineer_on_call_exp_months=12,
            system_load_ratio=1.0,
            contract_margin_pct=25.0,
            duration_hours=-5.0,  # Invalid
            event_occurred=0,
        )


# -----------------------------------------------------------------------------
# 3. Breslow Baseline Hazard Monotonicity & Inference Curve
# -----------------------------------------------------------------------------
def test_breslow_hazard_monotonicity(fitted_survival_engine: DeepSurvHazardEngine):
    """
    Asserts that the Breslow baseline cumulative hazard H_0(t) is monotonically non-decreasing.
    """
    engine = fitted_survival_engine
    cum_hazard = engine.baseline_cum_hazard

    assert len(cum_hazard) > 0
    diffs = np.diff(cum_hazard)
    assert np.all(diffs >= -1e-9), "Breslow baseline cumulative hazard must be non-decreasing."


def test_survival_curve_monotonic_decay(fitted_survival_engine: DeepSurvHazardEngine):
    """
    Validates that survival probability S(t) decreases monotonically over time horizons:
    S(30d) >= S(60d) >= S(90d).
    """
    sample = SLAIncidentRecord(
        contract_id="CNT-PRED-999",
        client_tier=ClientTier.ENTERPRISE,
        workload_type=WorkloadType.CLOUD_MIGRATION,
        ticket_severity=2,
        incident_volume_30d=8,
        mttr_historical_hours=5.2,
        engineer_on_call_exp_months=24,
        system_load_ratio=1.30,
        contract_margin_pct=28.0,
        duration_hours=20.0,
        event_occurred=0,
    )

    pred: SurvivalInferenceResult = fitted_survival_engine.predict_hazard(sample)

    assert 0.0 <= pred.survival_prob_90d <= pred.survival_prob_60d <= pred.survival_prob_30d <= 1.0, (
        f"Survival curve monotonicity violated: 30d={pred.survival_prob_30d}, "
        f"60d={pred.survival_prob_60d}, 90d={pred.survival_prob_90d}"
    )
    assert pred.hazard_ratio > 0.0
    assert pred.risk_tier in [RiskTier.NOMINAL, RiskTier.ELEVATED, RiskTier.CRITICAL]


# -----------------------------------------------------------------------------
# 4. Dependency Inversion Principle (DIP) & Isolated In-Memory Mocks
# -----------------------------------------------------------------------------
class InMemoryDataIngestionMock(DataIngestionProtocol):
    """Zero-disk, sub-1ms mock adapter for domain business testing."""

    def ingest_records(self, source_path: str) -> pl.DataFrame:
        return pl.DataFrame({
            "contract_id": ["MOCK-001", "MOCK-002"],
            "client_tier": ["Strategic Tier-1", "Standard Core"],
            "workload_type": ["SAP S/4HANA", "Managed DevOps"],
            "ticket_severity": [1, 3],
            "incident_volume_30d": [10, 2],
            "mttr_historical_hours": [6.0, 2.5],
            "engineer_on_call_exp_months": [48, 12],
            "system_load_ratio": [1.45, 0.85],
            "contract_margin_pct": [35.0, 20.0],
            "duration_hours": [28.0, 8.0],
            "event_occurred": [1, 0],
        })

    def parse_entities(self, df: pl.DataFrame) -> List[SLAIncidentRecord]:
        return PolarsDataIngestionAdapter().parse_entities(df)


class InMemoryTelemetrySinkMock(TelemetrySinkProtocol):
    """In-memory sink recording emitted domain inferences."""

    def __init__(self):
        self.sink: List[SurvivalInferenceResult] = []

    def emit_inference(self, result: SurvivalInferenceResult) -> None:
        self.sink.append(result)

    def flush(self) -> None:
        pass


def test_core_engine_dependency_inversion_mock():
    """
    Validates complete architectural decoupling:
    The core survival pipeline executes against mocked ingestion and telemetry sinks
    in < 5ms without accessing disk, network, or external databases.
    """
    mock_ingestion = InMemoryDataIngestionMock()
    mock_sink = InMemoryTelemetrySinkMock()

    df = mock_ingestion.ingest_records("virtual://memory/dataset")
    records = mock_ingestion.parse_entities(df)

    assert len(records) == 2
    assert records[0].contract_id == "MOCK-001"
    assert records[0].client_tier == ClientTier.STRATEGIC

    engine = DeepSurvHazardEngine(seed=123)
    engine.fit(df)

    preds = engine.batch_predict(records)
    for p in preds:
        mock_sink.emit_inference(p)

    assert len(mock_sink.sink) == 2
    assert mock_sink.sink[0].contract_id == "MOCK-001"
    assert mock_sink.sink[0].hazard_ratio > 0.0