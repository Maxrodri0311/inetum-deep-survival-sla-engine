"""
src/domain/contracts.py - Inversion of Dependencies (DIP) Protocols.
All data ingestion, algorithmic calculation, and delivery layers depend strictly
on these abstract interfaces without concrete storage or vendor coupling.
"""

from typing import Any, Dict, List, Optional, Protocol
import polars as pl
from .entities import SLAIncidentRecord, SurvivalInferenceResult


class DataIngestionProtocol(Protocol):
    """Abstract protocol for high-throughput tabular dataset ingestion (Polars / DuckDB)."""
    def ingest_records(self, source_path: str) -> pl.DataFrame:
        """Loads and returns an optimized lazy/eager Polars DataFrame."""
        ...

    def parse_entities(self, df: pl.DataFrame) -> List[SLAIncidentRecord]:
        """Validates and parses raw records into domain entities."""
        ...


class SurvivalEngineProtocol(Protocol):
    """Abstract protocol for Neural and Parametric Survival Analysis engines."""
    def fit(self, training_data: pl.DataFrame) -> None:
        """Calibrates baseline hazard functions and neural parameters."""
        ...

    def predict_hazard(self, record: SLAIncidentRecord) -> SurvivalInferenceResult:
        """Infers non-linear hazard ratios and survival curves S(t|x)."""
        ...

    def batch_predict(self, records: List[SLAIncidentRecord]) -> List[SurvivalInferenceResult]:
        """High-throughput vectorized inference over multiple contracts."""
        ...


class TelemetrySinkProtocol(Protocol):
    """Abstract protocol for PostgreSQL audit telemetry and SLA breach logging."""
    def persist_inferences(self, results: List[SurvivalInferenceResult]) -> int:
        """Emits predictions to telemetry sinks returning written record count."""
        ...


class TUIDeliveryProtocol(Protocol):
    """Abstract protocol for CLI/TUI executive rendering."""
    def render_dashboard(self, results: List[SurvivalInferenceResult]) -> None:
        """Displays formatted survival curves and hazard tiers in console."""
        ...