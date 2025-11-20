Halo.OS Performance Harness — Tracepoint Specification

Version: 1.0 — Maintained by Latorre Engineering

This document defines all LTTng-UST tracepoints used in the Halo.OS VBS Performance Harness.
These tracepoints provide the basis for measuring:

End-to-end perception → planning → control latency

High-percentile jitter

NPU virtualization overhead

VBS actuation timing

All naming is stable and versioned to ensure reproducibility across hardware targets.

1. Overview

The harness instruments key moments in the perception and control pipeline using lightweight, zero-copy LTTng-UST tracepoints.

Each tracepoint records:

A monotonic nanosecond timestamp

A stable event name

An optional payload (frame ID, queue depth, NPU job ID…)

Tracepoints are defined in:

tracepoints/halo_tracepoints.h


And are enabled at runtime via:

lttng create <session>
lttng enable-event --userspace 'halo:*'
lttng start

2. Tracepoint Categories

The harness defines four categories of tracepoints:

Sensor & Perception

Planning

Control & Actuation (VBS)

NPU Virtualization & Scheduling

Below is the canonical list of events.

3. Sensor & Perception Tracepoints

These measure the early pipeline from raw sensor input to model output.

3.1 halo:camera_frame_ingest

Triggered when the RT demo receives a decoded camera frame.

Payload:

uint64_t frame_id

uint32_t width

uint32_t height

Use: Start of end-to-end latency chain.

3.2 halo:perception_start

Triggered immediately before the perception model execution.

Payload:

uint64_t frame_id

Use: Perception compute latency; tracking pre-processing overhead.

3.3 halo:perception_end

Triggered immediately after the model finishes execution.

Payload:

uint64_t frame_id

float inference_ms

Use:

Perception → NPU → host latency

NPU scheduling overhead (via correlation with NPU events)

4. Planning Tracepoints

Capturing the classical decision-making stage.

4.1 halo:planning_start

Planning logic receives perception output.

Payload:

uint64_t frame_id

Use: Chain-of-custody from perception → planning.

4.2 halo:planning_end

Planning output is generated (e.g., trajectory, deceleration command).

Payload:

uint64_t frame_id

float planning_ms

Use: Planning compute latency; jitter analysis.

5. Control & VBS (Vehicle Bus System)

These tracepoints measure the actuation output path — the point where the ECU makes decisions that affect real vehicles.

5.1 halo:control_output

Triggered when control produces the final command (e.g. brake torque).

Payload:

uint64_t frame_id

float brake_command

Use:

Start of actuation latency

QoS verification under load

5.2 halo:vbs_brake_actuate

Triggered when the VBS module confirms the brake command was delivered/applied.

Payload:

uint64_t frame_id

float applied_brake_torque

Use:

End of end-to-end latency chain

Measurement anchor for camera → brake time

6. NPU Virtualization & Scheduling Tracepoints

These measure NPU queue behavior, job execution time, and virtualization overhead.

6.1 halo:npu_job_enqueue

Triggered when a perception task (or secondary AI workload) is queued for NPU execution.

Payload:

uint64_t job_id

uint64_t frame_id

uint32_t queue_depth

Use:

Detect NPU contention

Baseline for virtualization overhead

6.2 halo:npu_job_start

Triggered when the NPU scheduler begins executing the job.

Payload:

uint64_t job_id

Use:

Queue → start latency

Hardware scheduling behavior

6.3 halo:npu_job_end

Triggered when NPU computation finishes.

Payload:

uint64_t job_id

float exec_ms

Use:

NPU execution duration

Virtualization overhead vs. bare-metal

7. Event Timing Relationships

These tracepoints form a directed timeline:

camera_frame_ingest
   ↓
perception_start
   ↓
perception_end
   ↓
planning_start
   ↓
planning_end
   ↓
control_output
   ↓
vbs_brake_actuate


NPU events run in parallel but correlate with perception:

npu_job_enqueue → npu_job_start → npu_job_end

8. End-to-End Latency Calculation

End-to-end latency is computed as:

latency_ms =
  timestamp(vbs_brake_actuate) 
  - timestamp(camera_frame_ingest)


Perception, planning, and control latencies are each derived from their respective *_start and *_end event pairs.

9. Jitter Calculation

The harness supports:

p99.9 jitter

p99.99 jitter (primary Halo.OS claim)

windowed jitter over fixed intervals

Jitter formula:

jitter = max_latency - median_latency


Over a sliding time window.

10. Validation & Tracepoint Integrity

Tracepoints adhere to three rules:

Must not allocate memory inside the trace call

Must not block

Order must remain stable between releases

The harness enforces these using static CI checks.

11. Future Extensions

Upcoming tracepoints (proposed):

halo:gpu_load_sample

halo:mem_qos_violation

halo:perception_deadline_miss

halo:vbs_bus_delay

halo:npu_thermal_throttle
