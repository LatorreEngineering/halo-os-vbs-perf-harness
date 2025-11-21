#!/usr/bin/env bash
# Wrapper for ci/analyze_vbs.py to be used in CI
# Usage: ./analyze_vbs.sh --trace TRACE_DIR --output OUTPUT_DIR [--npu-baseline BASELINE_MS]

set -euo pipefail

function usage() {
    echo "Usage: $0 --trace TRACE_DIR --output OUTPUT_DIR [--npu-baseline BASELINE_MS]"
    exit 1
}

TRACE_DIR=""
OUTPUT_DIR=""
NPU_BASELINE=""

# Parse arguments
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
        --npu-baseline)
            NPU_BASELINE="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            echo "Unexpected argument: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$TRACE_DIR" ]]; then
    echo "Error: --trace is required"
    usage
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "Error: --output is required"
    usage
fi

# Activate venv if exists
if [[ -f "venv/bin/activate" ]]; then
    source venv/bin/activate
fi

# Find the events file
EVENTS_FILE="$TRACE_DIR/events.jsonl"
if [[ ! -f "$EVENTS_FILE" ]]; then
    echo "Error: events file not found: $EVENTS_FILE"
    exit 1
fi

# Build Python command
PY_CMD=("python3" "ci/analyze_vbs.py" "$EVENTS_FILE" "--output" "$OUTPUT_DIR")
if [[ -n "$NPU_BASELINE" ]]; then
    PY_CMD+=("--npu-baseline" "$NPU_BASELINE")
fi

# Run analysis
echo "Running analysis on $EVENTS_FILE..."
"${PY_CMD[@]}"
echo "Analysis completed. Results in $OUTPUT_DIR"
