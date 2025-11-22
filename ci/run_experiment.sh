#!/bin/bash
set -euo pipefail

RUN_DIR="$1"
DURATION="${2:-120}"
SCENARIO="${3:-aeb_120kmh}"
shift 3  # Args

log() { echo "[$(date)] $1"; }

log "Running $SCENARIO experiment ($DURATION s)"

# Load VBSPro
export LD_LIBRARY_PATH="${BUILD_DIR:-build}/install/lib:$LD_LIBRARY_PATH"
vbs_router &  # Start daemon
ROUTER_PID=$!

# LTTng session
lttng create "$RUN_DIR" -o "$RUN_DIR"
lttng enable-event -u -a  # All user-space
lttng start

# Mock workload (AEB: 120km/h camera→brake loop)
for i in $(seq 1 $((DURATION * 10))); do  # 10Hz sim
    # Mock events (integrate your tracepoints)
    echo "TRACE: camera_frame $i" | lttng ustd  # Pipe to trigger
    sleep 0.1
done

lttng stop
lttng destroy
kill $ROUTER_PID

# Dump to JSONL
babeltrace "$RUN_DIR/tracing" > "$RUN_DIR/events.jsonl" || log "Babeltrace non-fatal"

log "Experiment done: $RUN_DIR/events.jsonl"
