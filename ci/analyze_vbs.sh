#!/usr/bin/env bash
# Wrapper for ci/analyze_vbs.py for CI usage
# Usage: ./analyze_vbs.sh --trace TRACE_DIR --output OUTPUT_DIR [--npu-baseline BASELINE_MS] [--verbose]

set -euo pipefail

function usage() {
    echo "Usage: $0 --trace TRACE_DIR --output OUTPUT_DIR [--npu-baseline BASELINE_MS] [--verbose]"
    exit 1
}

TRACE_DIR=""
OUTPUT_DIR=""
NPU_BASELINE=""
VERBOSE=0

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
        --verbose)
            VERBOSE=1
            shift
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
    # shellcheck source=/dev/null
    source venv/bin/activate
fi

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Find all events.jsonl files
EVENT_FILES=()
while IFS= read -r -d $'\0' file; do
    EVENT_FILES+=("$file")
done < <(find "$TRACE_DIR" -maxdepth 1 -type f -name "events.jsonl" -print0)

if [[ ${#EVENT_FILES[@]} -eq 0 ]]; then
    echo "Error: No events.jsonl file found in $TRACE_DIR"
    exit 1
fi

# Run analysis on each events file
for EVENTS_FILE in "${EVENT_FILES[@]}"; do
    echo "Running analysis on $EVENTS_FILE..."
    PY_CMD=("python3" "ci/analyze_vbs.py" "$EVENTS_FILE" "--output" "$OUTPUT_DIR")
    if [[ -n "$NPU_BASELINE" ]]; then
        PY_CMD+=("--npu-baseline" "$NPU_BASELINE")
    fi
    if [[ $VERBOSE -eq 1 ]]; then
        PY_CMD+=("--verbose")
    fi

    if ! "${PY_CMD[@]}"; then
        echo "Error: Analysis failed for $EVENTS_FILE"
        exit 1
    fi
done

echo "✅ Analysis completed. Results saved in $OUTPUT_DIR"
