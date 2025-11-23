#!/usr/bin/env bash
# ci/generate_traces.sh
# Generate realistic LTTng-style trace data simulating AEB scenario
# This demonstrates the framework with data matching Li Auto's published metrics

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <output_directory>"
    exit 1
fi

OUTPUT_DIR="$1"
mkdir -p "${OUTPUT_DIR}"

EVENTS_FILE="${OUTPUT_DIR}/events.jsonl"

log "========================================"
log "Generating Realistic Trace Data"
log "========================================"
log "Scenario: AEB (Autonomous Emergency Braking) at 120 km/h"
log "Target metrics: ~100ms latency, <3ms jitter, ~20% NPU overhead"
log "Output: ${EVENTS_FILE}"

# Generate events using Python for better control
python3 << 'PYSCRIPT'
import json
import random
import sys

def generate_aeb_traces(num_frames=100):
    """
    Generate realistic AEB trace events:
    - Camera frames at ~30 FPS (33ms intervals)
    - Planning/inference on each frame
    - Brake actuation when needed
    - NPU inference with virtualization overhead
    """
    events = []
    base_time = 1000000000  # Start at 1 second (in nanoseconds)
    
    # Typical latencies (based on Li Auto whitepaper)
    camera_to_planning = 10_000_000  # 10ms
    planning_to_control = 80_000_000  # 80ms (includes inference)
    control_to_brake = 12_000_000    # 12ms
    
    # Add realistic variance (jitter)
    def add_jitter(base_ns, max_jitter_ms=3):
        jitter_ns = random.gauss(0, max_jitter_ms * 1_000_000 / 3)  # 3-sigma = max_jitter
        return int(base_ns + jitter_ns)
    
    for frame_id in range(1, num_frames + 1):
        frame_time = base_time + (frame_id * 33_333_333)  # ~30 FPS
        
        # Camera frame received
        events.append({
            'timestamp_ns': add_jitter(frame_time),
            'event_name': 'halo_camera_frame_received',
            'fields': {'frame_id': frame_id, 'camera_id': 'front', 'resolution': '1920x1080'}
        })
        
        # Planning start (includes NPU inference)
        planning_start = add_jitter(frame_time + camera_to_planning)
        events.append({
            'timestamp_ns': planning_start,
            'event_name': 'halo_planning_start',
            'fields': {'frame_id': frame_id, 'scenario': 'aeb'}
        })
        
        # NPU inference (happens during planning)
        npu_start = planning_start + 5_000_000  # 5ms into planning
        # Virtualization adds ~20% overhead: 15ms native → 18ms virtualized
        native_inference = 15_000_000
        virtualized_inference = int(native_inference * 1.20)
        
        events.append({
            'timestamp_ns': npu_start,
            'event_name': 'halo_npu_inference_start',
            'fields': {'inference_id': frame_id, 'model': 'object_detection', 'mode': 'virtualized'}
        })
        
        events.append({
            'timestamp_ns': add_jitter(npu_start + virtualized_inference, 0.5),
            'event_name': 'halo_npu_inference_end',
            'fields': {'inference_id': frame_id, 'objects_detected': random.randint(1, 5)}
        })
        
        # Planning end
        planning_end = add_jitter(frame_time + camera_to_planning + planning_to_control)
        events.append({
            'timestamp_ns': planning_end,
            'event_name': 'halo_planning_end',
            'fields': {'frame_id': frame_id, 'decision': 'brake' if frame_id % 10 < 3 else 'cruise'}
        })
        
        # Control command (only if braking needed)
        if frame_id % 10 < 3:  # 30% of frames need braking
            control_time = add_jitter(planning_end + 2_000_000)
            events.append({
                'timestamp_ns': control_time,
                'event_name': 'halo_control_command_sent',
                'fields': {'frame_id': frame_id, 'command': 'brake', 'intensity': random.randint(50, 100)}
            })
            
            # Brake actuation (end-to-end completion)
            brake_time = add_jitter(control_time + control_to_brake)
            events.append({
                'timestamp_ns': brake_time,
                'event_name': 'halo_brake_actuated',
                'fields': {'frame_id': frame_id, 'pressure_bar': random.randint(30, 80)}
            })
    
    return events

# Generate events
events = generate_aeb_traces(num_frames=100)

# Sort by timestamp
events.sort(key=lambda e: e['timestamp_ns'])

# Write to JSONL
output_file = sys.argv[1] if len(sys.argv) > 1 else 'events.jsonl'
with open(output_file, 'w') as f:
    for event in events:
        f.write(json.dumps(event) + '\n')

print(f'Generated {len(events)} events')
print(f'Saved to: {output_file}')

PYSCRIPT "${EVENTS_FILE}"

log "========================================"
log "Trace generation completed"
log "========================================"
log "Generated: $(wc -l < "${EVENTS_FILE}") events"
log ""
log "Event types:"
grep -o '"event_name":"[^"]*"' "${EVENTS_FILE}" | sort | uniq -c
log ""
log "Ready for analysis: python3 ci/analyze_vbs.py ${EVENTS_FILE}"

exit 0
