@echo off
setlocal enabledelayedexpansion

echo ================================================================================
echo   INETUM DEEP SURVIVAL SLA ENGINE
echo   Autonomous Lifecycle Hazard Analytics, TUI Triage and Performance Benchmarks
echo ================================================================================
echo.

echo [1/5] Synthesizing Calibrated Stochastic SLA Telemetry (50,000 observations)...
python src/data_generator.py --records 50000
if %ERRORLEVEL% NEQ 0 (echo [ERROR] Data generator failed && exit /b %ERRORLEVEL%)

echo.
echo [2/5] Calibrating DeepSurv Neural Proportional Hazards ^& Breslow Baseline...
python src/core_engine.py
if %ERRORLEVEL% NEQ 0 (echo [ERROR] Core engine failed && exit /b %ERRORLEVEL%)

echo.
echo [3/5] Launching Interactive Executive CLI/TUI Live Risk Triage Console...
python src/interface.py
if %ERRORLEVEL% NEQ 0 (echo [ERROR] Executive TUI failed && exit /b %ERRORLEVEL%)

echo.
echo [4/5] Executing Production Verification Suite (Pytest Mathematical Invariants)...
python -m pytest tests/ -v
if %ERRORLEVEL% NEQ 0 (echo [ERROR] Pytest suite failed && exit /b %ERRORLEVEL%)

echo.
echo [5/5] Running Dual-Tier Quantitative Latency ^& Memory Benchmarks (30 iterations)...
python tests/benchmark.py
if %ERRORLEVEL% NEQ 0 (echo [ERROR] Benchmark failed && exit /b %ERRORLEVEL%)

echo.
echo ================================================================================
echo   Execution Complete: All Invariants, TUI Panels and SLA Latencies PASSED!
echo ================================================================================