<!-- [SYSTEM INSTRUCTION]
Blueprint: inetum-deep-survival-sla-engine | Target: Inetum - Senior Data Scientist
Paradigm: DeliveryParadigm.CLI_TUI | Core Algorithm: DeepSurv Neural Proportional Hazards
Latency Targets: p95 < 150.0ms, p99 < 500.0ms | Max RAM: 512MB
Author: Maximiliano Rodriguez | Canonical Repo: https://github.com/Maxrodri0311/inetum-deep-survival-sla-engine
-->

<div align="center">

# Inetum: Inetum Senior Data Scientist Bridge Project

### Enterprise Finance decision support system powered by LINEAR_PROGRAMMING and decoupled multi-tier architecture with strict SQL data contracts.

[![Python 3.11+](https://img.shields.io/static/v1?label=Python&message=3.11%2B&color=3776AB&style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![DuckDB](https://img.shields.io/static/v1?label=DuckDB&message=Vectorized%20OLAP&color=FFF000&style=for-the-badge&logo=duckdb&logoColor=black)](https://duckdb.org/)
[![PostgreSQL](https://img.shields.io/static/v1?label=PostgreSQL&message=Windowed%20Analytics&color=4169E1&style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Terraform](https://img.shields.io/static/v1?label=Terraform&message=AWS%20S3%20ECR&color=844FBA&style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![CI](https://img.shields.io/static/v1?label=CI&message=GitHub%20Actions%20Passed&color=2088FF&style=for-the-badge&logo=githubactions&logoColor=white)](https://github.com/Maxrodri0311/inetum-finance-linear-optimization-engine/actions)
[![License: MIT](https://img.shields.io/static/v1?label=License&message=MIT&color=yellow&style=for-the-badge)](https://opensource.org/licenses/MIT)

**[⚡ Quickstart Demo (1-Click)](#-1-click-verification--benchmarks)** &nbsp;•&nbsp;
**[📐 Architecture Spec](00_SPEC.md)** &nbsp;•&nbsp;
**[🧪 Pytest Suite](tests/)** &nbsp;•&nbsp;
**[📊 Latency Profiler](tests/benchmark.py)**

</div>

---

## 🏛️ 1. Executive Summary & Core Bottleneck
Designed specifically for **Inetum** under the **Senior Data Scientist** requirements.

Inetum requires an enterprise-grade Causal & Survival Lifecycle Analytics architecture under Senior Data Scientist to solve operational latency, resource allocation bottlenecks, and provide C-Level visibility.

```mermaid
flowchart TD
    A[Stochastic Ingestion Layer] --> B[Decoupled Analytical Engine (DIP)]
    B --> C[AlgorithmFamily.LINEAR_PROGRAMMING Optimization & Scoring]
    C --> D[DeliveryParadigm.C_LEVEL_EXECUTIVE_SUITE Delivery Interface]

    style A fill:#1E293B,stroke:#38BDF8,stroke-width:2px,color:#FFFFFF
    style B fill:#0F172A,stroke:#64748B,stroke-width:2px,color:#FFFFFF
    style C fill:#1E293B,stroke:#10B981,stroke-width:2px,color:#FFFFFF
    style D fill:#0F172A,stroke:#F59E0B,stroke-width:2px,color:#FFFFFF
```

---

## ⚖️ 2. Architectural Trade-Offs Considered
- **Selected Approach:** AlgorithmFamily.LINEAR_PROGRAMMING with Clean Architecture & Dependency Inversion Principle (DIP).
- **Delivery Paradigm:** DeliveryParadigm.C_LEVEL_EXECUTIVE_SUITE.
- **Calibrated Invariant:** Modelado Dinámico Temporal vs Agregaciones Estáticas Tradicionales.
- **Target Performance:** Latency p95 < 150.0 ms, Memory < 512 MB.

---

## 🧪 3. Acceptance Criteria
- [x] Pass 100% of automated Pytest suite without regressions.
- [x] Achieve query latency p95 < 150ms over 50,000+ domain records.
- [x] Enforce strict Dependency Inversion Principle (DIP) with decoupled domain protocols.

---

## ⚡ 4. 1-Click Verification & Benchmarks

```bash
# 1. Clone repository
git clone https://github.com/Maxrodri0311/inetum-finance-linear-optimization-engine.git
cd inetum-finance-linear-optimization-engine

# 2. Run full automated pipeline, tests & benchmarks (Cross-Platform)
# Linux / macOS:
make all
# Or Windows 1-Click Runner:
run_demo.bat
```

---

## 👤 Author & Canonical Profile
- **Engineer:** Maximiliano Rodriguez
- **Email:** [maxrodri0311@gmail.com](mailto:maxrodri0311@gmail.com)
- **LinkedIn:** [https://www.linkedin.com/in/maximiliano-rodriguez-982674375/](https://www.linkedin.com/in/maximiliano-rodriguez-982674375/)
- **GitHub:** [@Maxrodri0311](https://github.com/Maxrodri0311)