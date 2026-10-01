"""
src/data_generator.py - Calibrated Stochastic Domain Data Generator.
Physics: Non-homogeneous Weibull Time-to-Event Hazard Process for Inetum Managed Services.
Calibrated for enterprise SLA monitoring, workload degradation, and right-censoring dynamics.
Zero unverified placeholders; leverages Polars for vectorized sub-second Parquet serialization.
"""

import argparse
import os
from pathlib import Path
import time
from typing import Dict, List, Optional, Tuple

import numpy as np
import polars as pl

import sys

# Ensure project root is in sys.path when executed directly
_project_root = str(Path(__file__).resolve().parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

try:
    from src.domain.entities import ClientTier, SLAIncidentRecord, WorkloadType
except ImportError:
    from domain.entities import ClientTier, SLAIncidentRecord, WorkloadType


class StochasticDataPhysicsGenerator:
    """
    Generates high-fidelity SLA lifecycle observations adhering to a calibrated
    Weibull Proportional Hazards process with non-informative right-censorship.
    """

    def __init__(
        self,
        seed: int = 42,
        weibull_shape: float = 1.35,
        weibull_scale: float = 550.0,
    ):
        self.seed = seed
        self.shape = weibull_shape
        self.scale = weibull_scale
        self.rng = np.random.default_rng(seed)

    def generate(self, num_records: int = 50000) -> pl.DataFrame:
        """
        Executes vectorized stochastic physics generation over num_records observations.
        Returns a strongly-typed Polars DataFrame.
        """
        # 1. Identifiers & Categorical Dimensions
        contract_ids = [f"CNT-INETUM-{i:07d}" for i in range(1, num_records + 1)]

        client_tiers = [
            ClientTier.STRATEGIC.value,
            ClientTier.ENTERPRISE.value,
            ClientTier.STANDARD.value,
        ]
        tier_probs = [0.25, 0.45, 0.30]
        chosen_tiers = self.rng.choice(client_tiers, p=tier_probs, size=num_records)

        workloads = [
            WorkloadType.CLOUD_MIGRATION.value,
            WorkloadType.MANAGED_DEVOPS.value,
            WorkloadType.AI_DATA_PIPELINE.value,
            WorkloadType.SAP_S4HANA.value,
            WorkloadType.CYBERSECURITY_SOC.value,
        ]
        workload_probs = [0.28, 0.26, 0.18, 0.16, 0.12]
        chosen_workloads = self.rng.choice(workloads, p=workload_probs, size=num_records)

        # 2. Continuous & Discrete Covariates
        # Severity: 1 (Critical Outage) to 4 (Minor Ticket)
        severities = self.rng.choice([1, 2, 3, 4], p=[0.12, 0.28, 0.40, 0.20], size=num_records)

        # 30-day incident rolling volume ~ Poisson(lambda=14)
        incident_volumes = self.rng.poisson(lam=14, size=num_records)

        # Historical MTTR ~ Gamma(shape=3.0, scale=3.2) -> mean ~ 9.6 hours
        mttr_history = np.round(self.rng.gamma(shape=3.0, scale=3.2, size=num_records), 2)
        mttr_history = np.clip(mttr_history, 1.0, 48.0)

        # Engineer experience in months ~ Uniform(3, 120)
        engineer_exp = self.rng.integers(3, 121, size=num_records)

        # System load ratio ~ Beta(2.5, 3.5) scaled to [0.35, 1.85]
        load_ratios = np.round(self.rng.beta(2.5, 3.5, size=num_records) * 1.5 + 0.35, 3)

        # Contract margin pct ~ Gaussian(mean=28.5%, std=7.5%)
        margins = np.round(self.rng.normal(loc=28.5, scale=7.5, size=num_records), 2)
        margins = np.clip(margins, -15.0, 65.0)

        # 3. Stochastic Proportional Hazards Linear Predictor (beta * X)
        tier_risk_weights = {
            ClientTier.STRATEGIC.value: 0.45,
            ClientTier.ENTERPRISE.value: 0.15,
            ClientTier.STANDARD.value: -0.10,
        }
        workload_risk_weights = {
            WorkloadType.CLOUD_MIGRATION.value: 0.35,
            WorkloadType.MANAGED_DEVOPS.value: -0.15,
            WorkloadType.AI_DATA_PIPELINE.value: 0.25,
            WorkloadType.SAP_S4HANA.value: 0.40,
            WorkloadType.CYBERSECURITY_SOC.value: 0.10,
        }

        tier_effects = np.array([tier_risk_weights[t] for t in chosen_tiers])
        workload_effects = np.array([workload_risk_weights[w] for w in chosen_workloads])

        beta_x = (
            tier_effects
            + workload_effects
            + (5 - severities) * 0.30
            + (incident_volumes - 14) * 0.035
            + (mttr_history - 9.6) * 0.045
            - (engineer_exp / 120.0) * 0.55
            + (load_ratios - 0.95) * 0.85
        )

        # 4. Weibull Time-to-Event Inversion: T = scale * (-ln(U) / exp(beta_x))^(1 / gamma)
        uniform_noise = self.rng.uniform(0.0001, 0.9999, size=num_records)
        t_event = self.scale * (-np.log(uniform_noise) / np.exp(beta_x)) ** (1.0 / self.shape)

        # 5. Right-Censorship: Observation or Resolution Target window C ~ Uniform(48, 360) hrs
        c_censoring = self.rng.uniform(48.0, 360.0, size=num_records)

        durations = np.round(np.minimum(t_event, c_censoring), 2)
        events = (t_event <= c_censoring).astype(np.int32)

        # 6. Assembly into Vectorized Polars DataFrame
        df = pl.DataFrame({
            "contract_id": contract_ids,
            "client_tier": chosen_tiers,
            "workload_type": chosen_workloads,
            "ticket_severity": severities,
            "incident_volume_30d": incident_volumes,
            "mttr_historical_hours": mttr_history,
            "engineer_on_call_exp_months": engineer_exp,
            "system_load_ratio": load_ratios,
            "contract_margin_pct": margins,
            "duration_hours": durations,
            "event_occurred": events,
        })
        return df

    def to_domain_entities(self, df: pl.DataFrame) -> List[SLAIncidentRecord]:
        """Maps Polars rows to strongly-validated Pydantic domain entities."""
        records = []
        for row in df.iter_rows(named=True):
            records.append(
                SLAIncidentRecord(
                    contract_id=row["contract_id"],
                    client_tier=ClientTier(row["client_tier"]),
                    workload_type=WorkloadType(row["workload_type"]),
                    ticket_severity=row["ticket_severity"],
                    incident_volume_30d=row["incident_volume_30d"],
                    mttr_historical_hours=float(row["mttr_historical_hours"]),
                    engineer_on_call_exp_months=row["engineer_on_call_exp_months"],
                    system_load_ratio=float(row["system_load_ratio"]),
                    contract_margin_pct=float(row["contract_margin_pct"]),
                    duration_hours=float(row["duration_hours"]),
                    event_occurred=row["event_occurred"],
                )
            )
        return records


def generate_domain_dataset(
    num_records: int = 50000,
    output_path: str = "data/raw_dataset.parquet",
    seed: int = 42,
) -> pl.DataFrame:
    """
    Main generator facade. Produces calibrated SLA data and saves to Parquet.
    """
    print(f"[Data Generator] Simulating {num_records:,} calibrated SLA records for Inetum...")
    t0 = time.perf_counter()

    generator = StochasticDataPhysicsGenerator(seed=seed)
    df = generator.generate(num_records=num_records)

    out_file = Path(output_path)
    out_file.parent.mkdir(parents=True, exist_ok=True)
    df.write_parquet(out_file)

    elapsed_ms = (time.perf_counter() - t0) * 1000
    event_rate = df["event_occurred"].mean() * 100

    print(
        f"[Data Generator] Successfully synthesized {len(df):,} records in {elapsed_ms:.1f}ms "
        f"-> {output_path} (SLA Breach Rate: {event_rate:.1f}%, Right-Censored: {100 - event_rate:.1f}%)"
    )
    return df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Calibrated Stochastic Data Generator.")
    parser.add_argument("--records", type=int, default=50000, help="Number of SLA observations")
    parser.add_argument("--output", type=str, default="data/raw_dataset.parquet", help="Parquet target path")
    parser.add_argument("--seed", type=int, default=42, help="Deterministic PRNG seed")
    args = parser.parse_args()

    generate_domain_dataset(
        num_records=args.records,
        output_path=args.output,
        seed=args.seed,
    )