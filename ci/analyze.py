#!/usr/bin/env bash
# run_vbs_analysis.sh - Run Halo.OS VBS performance analysis
# Usage:
#   ./run_vbs_analysis.sh --trace <trace_dir> --output <output_dir> [--start_event <start>] [--end_event <end>]

set -euo pipefail
IFS=$'\n\t'

# -------------------------------
# Helper functions
# -------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

usage() {
    echo "Usage: $0 --trace <trace_dir> --output <output_dir> [--start_event <start>] [--end_event <end>]"
    exit 1
}

# -------------------------------
# Parse arguments
# -------------------------------
TRACE_DIR=""
OUTPUT_DIR=""
START_EVENT="halo_camera_ingest"
END_EVENT="halo_brake_actuate"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --trace)
            TRACE_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --start_event)
            START_EVENT="$2"
            shift 2
            ;;
        --end_event)
            END_EVENT="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# -------------------------------
# Validate inputs
# -------------------------------
if [[ -z "$TRACE_DIR" || -z "$OUTPUT_DIR" ]]; then
    usage
fi

if [[ ! -d "$TRACE_DIR" ]]; then
    log "ERROR: Trace directory does not exist: $TRACE_DIR"
    exit 1
fi

PYTHON_SCRIPT="./analyze_vbs.py"
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    log "ERROR: Python analysis script not found: $PYTHON_SCRIPT"
    exit 1
fi

# -------------------------------
# Prepare output directory
# -------------------------------
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RUN_OUTPUT="$OUTPUT_DIR/run_$TIMESTAMP"
mkdir -p "$RUN_OUTPUT"
log "Output directory for this run: $RUN_OUTPUT"

# -------------------------------
# Run performance analysis
# -------------------------------
log "Starting VBS performance analysis..."
python3 "$PYTHON_SCRIPT" \
    --trace "$TRACE_DIR" \
    --output "$RUN_OUTPUT" \
    --start_event "$START_EVENT" \
    --end_event "$END_EVENT"

log "VBS performance analysis completed successfully."
log "Results saved in $RUN_OUTPUT"
