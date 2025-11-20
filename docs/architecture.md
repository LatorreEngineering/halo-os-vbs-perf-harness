Halo.OS Performance Harness — Architecture Overview

Version: 1.0 — Maintained by Latorre Engineering

This document describes the internal architecture of the Halo.OS VBS Performance Harness, including its major components, execution model, instrumentation flow, and how the harness integrates with Halo.OS builds and hardware targets.

1. Purpose of the Harness

The performance harness enables independent, reproducible benchmarking of Halo.OS across three key domains:

End-to-end latency (sensor → perception → planning → control → actuation)

Jitter stability at high percentiles (p99.9, p99.99)

NPU virtualization overhead under shared workloads

It is designed to be reproducible across vendors, hardware, and OS revisions.

2. High-Level Architecture
┌────────────────────────────────────────────────────────────┐
│                    halo-os-vbs-perf-harness                │
└────────────────────────────────────────────────────────────┘
       │
       ├── Manifest Layer (pinned)
       │
       ├── Build Layer (instrumented Halo.OS demo)
       │
       ├── Execution Layer (VBS scenario runner)
       │
       ├── Tracing Layer (LTTng-UST instrumentation)
       │
       ├── Data Layer (raw events, telemetry)
       │
       └── Analysis Layer (latency, jitter, NPU overhead)

3. Manifest Layer

The harness uses a pinned Halo.OS manifest stored in:

manifests/pinned_manifest.xml


This ensures:

Exact reproducibility

Fixed dependency graph across modules

Same build state Li Auto used in Nov-2025 measurements

The manifest is loaded using Google’s repo tool to reconstruct the full source tree.

4. Build Layer

The build system:

Initializes the repository using the pinned manifest

Syncs all dependencies

Selects the appropriate toolchain (Jetson / SemiDrive / x86)

Builds the instrumented perception-planning-control demo

Build Output Directory
apps/rt_demo/build/rt_demo


This demo is compiled with tracepoints embedded, enabling precise instrumentation.

5. Execution Layer

The execution layer triggers a deterministic VBS (Vehicle Bus System) test scenario:

ci/run_experiment.sh <test_id> <duration_s>


Execution responsibilities:

Start Halo.OS app

Replay or emulate sensor frames

Apply load profiles (CPU/GPU/NPU)

Generate VBS messages

Capture reactions in the control loop

Target platforms supported:

Platform	Purpose
Jetson AGX Orin	Full HW test
SemiDrive E3650	Full HW test
x86	Analysis / dry-run only
6. Tracing Layer

The core of the architecture.

Instrumentation uses LTTng-UST tracepoints placed at:

Camera frame ingest

Perception start / end

Planning start / end

Control output

VBS brake actuation

NPU scheduling events (begin / end)

Tracepoints are defined inside:

tracepoints/halo_tracepoints.h


LTTng captures timestamps at nanosecond resolution, enabling statistically valid jitter analysis.

7. Data Layer

Raw data is stored in:

results/<test_id>/
│
├── events.jsonl      # Flattened event stream
├── raw_trace/        # Full LTTng session
└── metadata.json     # Test config, HW info


events.jsonl contains normalized event markers used for downstream processing.

8. Analysis Layer

The Python script:

ci/analyze.py


Performs:

8.1 Latency Calculation

Computes:

p50

p95

p99

p99.9

p99.99

End-to-end averages

Worst-case latency

8.2 Jitter Metrics

Jitter = max_latency - median_latency across windows.

8.3 NPU Virtualization Overhead

Computed from:

NPU job timestamps

Queueing times

Execution deltas

Formula used:

overhead = (virtualized_time - baseline_time) / baseline_time

9. Architecture Diagram
┌──────────────────────────────────────┐
│            Halo.OS Build             │
│        (from pinned manifest)        │
└──────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│      Instrumented RT Demo App        │
│ (perception → planning → control)    │
└──────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│           Execution Engine           │
│      (run_experiment.sh + VBS)       │
└──────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│          LTTng Tracepoints           │
│  (camera, NPU, planning, control…)   │
└──────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│         Raw Trace Data (.jsonl)      │
└──────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│           Python Analyzer            │
│  (latency, jitter, NPU overhead)     │
└──────────────────────────────────────┘

10. Key Architectural Principles

Reproducibility: pinned manifests, scriptable workflows

Transparency: open tracepoints, open analysis

Hardware-agnostic design: works on Orin and SemiDrive

Deterministic test execution: fixed scenarios

Separation of layers: build → execute → trace → analyze

Statistical validity: high-percentile jitter evaluation

11. Future Extensions

Planned expansions:

Multi-sensor scenario generation

Fault injection (CPU/GPU/NPU throttling)

AUTOSAR baseline comparison mode

Long-running soak tests (1–8 hours)

Real CAN/LIN integration support
