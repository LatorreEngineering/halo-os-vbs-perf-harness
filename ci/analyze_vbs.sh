#!/usr/bin/env bash
# ci/analyze_vbs.sh
# Wrapper for ci/analyze_vbs.py for CI usage
# Usage: ./analyze_vbs.sh --trace TRACE_DIR --output OUTPUT_DIR [--npu-baseline BASELINE_MS] [--verbose]

set -euo pipefail

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 --trace TRACE_DIR --output OUTPUT_DIR [--npu-baseline BASELINE_MS] [--verbose]"
    exit 1
}

log() { echo "[$(date +'%F %T')] $*"; }
error() { echo "[$(date +'%F %T')] ERROR: $*" >&2; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TRACE_DIR=""
OUTPUT_DIR=""
NPU_BASELINE=""
VERBOSE=0

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
        --help|-h)
            usage
            ;;
        -*)
            error "Unknown option: $1"
            usage
            ;;
        *)
            error "Unexpected argument: $1"
            usage
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate required arguments
# ---------------------------------------------------------------------------
[[ -n "$TRACE_DIR" ]] || { error "--trace is required"; usage; }
[[ -n "$OUTPUT_DIR" ]] || { error "--output is required"; usage; }

# ---------------------------------------------------------------------------
# Activate virtual environment if exists
# ---------------------------------------------------------------------------
if [[ -f "venv/bin/activate" ]]; then
    # shellcheck source=/dev/null
    source "venv/bin/activate"
fi

# ---------------------------------------------------------------------------
# Ensure output directory exists
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Find events files
# ---------------------------------------------------------------------------
EVENT_FILES=()
while IFS= read -r -d $'\0' file; do
    EVENT_FILES+=("$file")
done < <(find "$TRACE_DIR" -maxdepth 1 -type f -name "events.jsonl" -print0)

[[ ${#EVENT_FILES[@]} -gt 0 ]] || { error "No events.jsonl file found in $TRACE_DIR"; exit 1; }

# ---------------------------------------------------------------------------
# Run analysis on each events file
# ---------------------------------------------------------------------------
for EVENTS_FILE in "${EVENT_FILES[@]}"; do
    log "Running analysis on $EVENTS_FILE..."
    PY_CMD=("python3" "ci/analyze_vbs.py" "$EVENTS_FILE" "--output" "$OUTPUT_DIR")

    [[ -n "$NPU_BASELINE" ]] && PY_CMD+=("--npu-baseline" "$NPU_BASELINE")
    [[ $VERBOSE -eq 1 ]] && PY_CMD+=("--verbose")

    if ! "${PY_CMD[@]}"; then
        error "Analysis failed for $EVENTS_FILE"
        exit 1
    fi
done

log "✅ Analysis completed. Results saved in $OUTPUT_DIR"
