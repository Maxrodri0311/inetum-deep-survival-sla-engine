"""
tests/benchmark.py - Quantitative Latency & Memory Benchmark.
Architecture: Dual-Tier Latency SLA Profiling (Real-Time Single-Ticket Triage & Vectorized Batch Stream).
Enforces Production SLA Constraints:
  - Real-Time Single-Ticket Triage: p95 < 5.0 ms
  - Vectorized Batch Stream (500 records): p95 < 150.0 ms
  - Peak Memory Allocation: < 15.0 MB
"""

from pathlib import Path
import sys
import time
import tracemalloc
from typing import Dict, List

import numpy as np
import polars as pl

# Robust path resolution
project_root = str(Path(__file__).resolve().parent.parent)
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from src.core_engine import DeepSurvHazardEngine, PolarsDataIngestionAdapter
from src.data_generator import generate_survival_dataset


def run_benchmarks(iterations: int = 30, num_records: int = 10000) -> Dict[str, float]:
    if sys.platform == "win32":
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    print(f"[*] [Benchmark] Synthesizing calibrated dataset ({num_records:,} observations)...")
    df: pl.DataFrame = generate_survival_dataset(n_samples=num_records, seed=42)
    ingestion = PolarsDataIngestionAdapter()
    records = ingestion.parse_entities(df)

    print(f"[*] [Benchmark] Calibrating DeepSurvHazardEngine baseline hazard curve...")
    engine = DeepSurvHazardEngine(seed=42)
    engine.fit(df)

    # -------------------------------------------------------------------------
    # 1. Memory Profile (Isolated pass to avoid allocator instrumentation overhead)
    # -------------------------------------------------------------------------
    tracemalloc.start()
    _ = engine.batch_predict(records[:1000])
    _, peak_mem_bytes = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    peak_mem_mb = peak_mem_bytes / (1024.0 * 1024.0)

    # -------------------------------------------------------------------------
    # 2. Micro-Benchmark: Real-Time Single-Ticket Triage
    # -------------------------------------------------------------------------
    single_record = records[0]
    # Warmup
    _ = engine.predict_hazard(single_record)

    single_latencies: List[float] = []
    for _ in range(iterations * 2):
        t0 = time.perf_counter()
        _ = engine.predict_hazard(single_record)
        single_latencies.append((time.perf_counter() - t0) * 1000.0)

    p50_single = float(np.percentile(single_latencies, 50))
    p95_single = float(np.percentile(single_latencies, 95))
    p99_single = float(np.percentile(single_latencies, 99))

    # -------------------------------------------------------------------------
    # 3. Macro-Benchmark: Vectorized Stream Batch Triage (500 records/batch)
    # -------------------------------------------------------------------------
    batch_500 = records[:500]
    # Warmup
    _ = engine.batch_predict(batch_500)

    batch_latencies: List[float] = []
    for _ in range(iterations):
        t0 = time.perf_counter()
        _ = engine.batch_predict(batch_500)
        batch_latencies.append((time.perf_counter() - t0) * 1000.0)

    p50_batch = float(np.percentile(batch_latencies, 50))
    p95_batch = float(np.percentile(batch_latencies, 95))
    p99_batch = float(np.percentile(batch_latencies, 99))
    mean_batch_lat = float(np.mean(batch_latencies))
    batch_throughput = float(len(batch_500) / (mean_batch_lat / 1000.0))

    status_single = "PASS" if p95_single < 5.0 else "FAIL"
    status_batch = "PASS" if p95_batch < 150.0 else "FAIL"
    status_mem = "PASS" if peak_mem_mb < 15.0 else "FAIL"

    print("\n" + "=" * 74)
    print("  INETUM DEEP SURVIVAL SLA ENGINE - QUANTITATIVE BENCHMARK REPORT")
    print("=" * 74)
    print(f"  Dataset Population       : {num_records:,} total historical records")
    print(f"  Profiling Iterations     : {iterations} passes")
    print("-" * 74)
    print(f"  1. Real-Time Single-Ticket Triage:")
    print(f"     -> p50: {p50_single:.3f} ms | p95: {p95_single:.3f} ms | p99: {p99_single:.3f} ms")
    print(f"     -> Production SLA Target : p95 < 5.0 ms [{status_single}]")
    print("-" * 74)
    print(f"  2. Vectorized Stream Batch Triage (500 incidents):")
    print(f"     -> p50: {p50_batch:.2f} ms | p95: {p95_batch:.2f} ms | p99: {p99_batch:.2f} ms")
    print(f"     -> Mean Throughput       : {batch_throughput:,.1f} records/sec")
    print(f"     -> Production SLA Target : p95 < 150.0 ms [{status_batch}]")
    print("-" * 74)
    print(f"  3. Memory Footprint Profile:")
    print(f"     -> Peak Heap Allocation  : {peak_mem_mb:.2f} MB [SLA < 15.0 MB: {status_mem}]")
    print("=" * 74)

    # Formal Production Assertions
    assert p95_single < 5.0, f"Single-ticket SLA breached: p95={p95_single:.3f}ms >= 5.0ms target."
    assert p95_batch < 150.0, f"Batch SLA breached: p95={p95_batch:.2f}ms >= 150.0ms target."
    assert peak_mem_mb < 15.0, f"Memory threshold breached: peak={peak_mem_mb:.2f}MB >= 15.0MB."

    print("  [+] All quantitative SLA and memory constraints verified successfully.\n")

    return {
        "p50_single_ms": round(p50_single, 3),
        "p95_single_ms": round(p95_single, 3),
        "p50_batch_ms": round(p50_batch, 2),
        "p95_batch_ms": round(p95_batch, 2),
        "throughput_rps": round(batch_throughput, 1),
        "peak_mem_mb": round(peak_mem_mb, 2),
    }


if __name__ == "__main__":
    run_benchmarks()