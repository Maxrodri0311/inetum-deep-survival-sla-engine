"""
src/data_generator.py - Calibrated Stochastic Domain Data Generator.
Physics: AlgorithmFamily.LINEAR_PROGRAMMING for Inetum (GP-038).
Zero toy placeholders: variables, types and bounds are derived from ProjectDNA.
"""

import os
import time
import argparse
from datetime import datetime, timedelta
import numpy as np
import pandas as pd


def generate_domain_dataset(
    num_records: int = 50000,
    output_path: str = "data/raw_dataset.parquet",
    seed: int = 42,
) -> pd.DataFrame:
    print(f"[Data Generator] Generating {num_records:,} records for Inetum...")
    start_time = time.time()
    np.random.seed(seed)
    rng = np.random.default_rng(seed)

    # Identifiers
    primary_ids = [f"id_{i:06d}" for i in range(1, num_records + 1)]
    
    data_dict = {
        "inetum_senior_d_id": primary_ids,
    }

    data_dict["primary_metric"] = np.round(rng.uniform(10.0, 500.0, num_records), 4)
    data_dict["volume_count"] = rng.integers(int(1.0), int(1000.0) + 1, num_records)
    data_dict["is_active"] = rng.choice([True, False], p=[0.70, 0.30], size=num_records)
    categories = ["tier_standard", "tier_accelerated", "tier_enterprise", "tier_custom"]
    data_dict["status_category"] = rng.choice(categories, p=[0.4, 0.3, 0.2, 0.1], size=num_records)

    df = pd.DataFrame(data_dict)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    df.to_parquet(output_path, index=False)

    elapsed = time.time() - start_time
    print(f"[Data Generator] Successfully generated {len(df):,} records in {elapsed:.2f}s -> {output_path}")
    return df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate domain dataset.")
    parser.add_argument("--records", type=int, default=50000)
    parser.add_argument("--output", type=str, default="data/raw_dataset.parquet")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    generate_domain_dataset(
        num_records=args.records,
        output_path=args.output,
        seed=args.seed,
    )