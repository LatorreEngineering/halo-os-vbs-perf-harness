Halo.OS Performance Harness — Experiment Flow Guide

Version 1.0 — Maintained by Latorre Engineering

This document explains the full experimental workflow for running performance, latency, jitter, and NPU-virtualization measurements on Halo.OS using the VBS Performance Harness.

It is intended for engineers evaluating Halo.OS behavior on embedded hardware (Jetson, Semidrive) or virtual platforms.

1. Purpose

The harness measures:

End-to-end camera → perception → planning → control → brake latency

High-percentile p99.9 / p99.99 jitter

NPU virtualization overhead

Scheduling delays and pipeline stalls

Real-time determinism of the VBS module

This flow describes exactly what runs, in what order, and how results are produced.

2. High-Level Flow Overview

The experiment consists of four major phases:

1. Initialization
2. Runtime execution loop (tracepoint collection)
3. Data extraction
4. Offline analysis & visualization


These match the architecture of the harness:

         ┌───────────────┐
         │  Test Runner  │
         └───────┬───────┘
                 │
        ┌────────▼────────┐
        │  Halo.OS DUT    │
        │  (Instrumented) │
        └────────┬────────┘
                 │ Tracepoints
        ┌────────▼────────┐
        │   LTTng Session │
        └────────┬────────┘
                 │ CTF traces
        ┌────────▼────────┐
        │ Offline Analyzer│
        └──────────────────┘

3. Phase 1 — Initialization

This phase sets up the hardware or simulator, configures LTTng, and loads the RT demo.

3.1 Configure Hardware Platform

Supported targets:

NVIDIA Jetson (Xavier, Orin)

Semidrive AXERA-based Boards

Halo.OS QEMU VBS Image

Configure:

CPU governor (performance)

Disable frequency scaling

Set isolation mask for RT cores (if available)

Disable thermal throttling (if safe)

Example (Jetson):

sudo nvpmodel -m 0
sudo jetson_clocks

3.2 Load the Halo.OS Runtime

Boot Halo.OS via:

./flash_halo_os.sh


Or launch QEMU:

./run_halo_qemu.sh --vbs --rt-demo

3.3 Start LTTng Session
lttng create halo_session
lttng enable-event --userspace 'halo:*'
lttng start


All tracepoints listed in docs/tracepoints.md are now active.

4. Phase 2 — Runtime Execution Loop

This is the core of the experiment: running the RT demo in a controlled, repeatable loop.

The loop executes:

for frame in dataset:
    ingest_frame()
    run_perception()
    run_planning()
    run_control()
    actuation()


Each stage fires tracepoints.

4.1 Data Source Options
A) Synthetic Camera Stream

Default — reproducible for benchmarking.

Fixed resolution

Zero-copy ingestion

Permits deterministic frame timing

B) Real Dataset Playback

Use ROS-bag or MP4 sequence:

./run_rt_demo --input my_dataset.mp4

C) Live Camera

Supported on Jetson and Semidrive boards.

4.2 Runtime Timing Controls

The test runner supports:

Fixed frame rate mode (e.g., 30 FPS)

Burst mode (stress test)

Load shaping (adds CPU/NPU synthetic load)

Examples:

--fps 30
--burst 200
--cpu-load 40%
--npu-load 60%

5. Phase 3 — Data Extraction

Stop tracing:

lttng stop
lttng destroy


Extract traces:

./scripts/extract_traces.sh --output results/


Output:

results/
    traces/         # CTF files
    metadata.json   # Test config

6. Phase 4 — Offline Analysis

Run:

./analysis/analyze.py results/traces/


This tool performs:

6.1 End-to-End Latency

From:

camera_frame_ingest → vbs_brake_actuate


Graph output:

histogram

time series

boxplot

high-percentile table (p99, p99.9, p99.99)

6.2 Per-Stage Latency

Pairs:

perception_start ↔ perception_end

planning_start ↔ planning_end

control_output ↔ vbs_brake_actuate

6.3 NPU Virtualization Overhead

Using:

npu_job_enqueue → npu_job_start → npu_job_end


Reports:

queue_wait_ms

exec_time_ms

total_virtualization_overhead_ms

6.4 Jitter Analysis

Computes jitter over sliding windows:

window = 1s, 5s, 10s, full test


Outputs:

jitter heatmap

jitter envelope

cumulative distribution (CDF)

7. Pass/Fail Criteria (Optional)

The harness supports automated verdicts:

Metric	Threshold
End-to-end latency	< 50 ms
Perception jitter p99.9	< 1.5 ms
NPU virtualization overhead	< 2 ms
Actuation latency	< 5 ms

Set in:

config/test_profile.json

8. Example Timeline Visualization
cam_ingest ──► perception_start ──► perception_end ──► plan_start ──► plan_end ──► control_out ──► brake_actuate
      │                                 │                                        │
      └────────────── npu_job_enqueue → npu_job_start → npu_job_end ─────────────┘

9. Reproducibility Guidelines

To achieve reproducible results:

Warm up device: 60 seconds recommended

Fix CPU/GPU/NPU clock frequencies

Pin perception & planning threads to isolated cores

Repeat each experiment ≥ 3 times

Use synthetic input for baseline comparisons

10. Future Extensions

Planned enhancements:

Multi-sensor latency modeling (LiDAR + camera)

GPU tracepoints for concurrent workloads

Distributed multi-ECU timing correlation

Hardware brake emulator integration

