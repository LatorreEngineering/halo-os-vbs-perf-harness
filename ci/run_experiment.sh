#!/bin/bash
# ci/run_experiment.sh
# Purpose: Run Halo.OS experiment with LTTng tracing
# Usage: ./ci/run_experiment.sh <run_id> <duration_seconds> [--scenario SCENARIO] [--hardware MODE]

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source environment
[[ -f "${PROJECT_ROOT}/.env" ]] && source "${PROJECT_ROOT}/.env"

BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
RESULTS_DIR="${RESULTS_DIR:-${PROJECT_ROOT}/results}"

# Defaults
RUN_ID=""
DURATION=300
SCENARIO="aeb_120kmh"
HARDWARE_MODE="auto"

# ==================================================================
# Logging
# ==================================================================
log() { echo "[$(date +'%F %T')] $*"; }
error() { echo "[$(date +'%F %T')] ERROR: $*" >&2; }
fatal() { error "$@"; cleanup; exit 1; }

# ==================================================================
# Cleanup
# ==================================================================
LTTNG_SESSION=""
HALO_PID=""

cleanup() {
    log "Cleaning up..."
    [[ -n "$HALO_PID" ]] && kill -0 "$HALO_PID" 2>/dev/null && kill -TERM "$HALO_PID" 2>/dev/null || true
    [[ -n "$LTTNG_SESSION" ]] && lttng destroy "$LTTNG_SESSION" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# ==================================================================
# Argument Parsing
# ==================================================================
parse_args() {
    if [[ $# -lt 2 ]]; then
        cat << EOF
Usage: $0 <run_id> <duration_seconds> [OPTIONS]

Arguments:
    run_id              Unique identifier (alphanumeric, dash, underscore)
    duration_seconds    Duration in seconds (positive integer)

Options:
    --scenario SCENARIO  Default: aeb_120kmh
    --hardware MODE      auto, hardware, simulation (default: auto)
    --help, -h           Show help

EOF
        exit 0
    fi

    RUN_ID="$1"
    DURATION="$2"
    shift 2

    while [[ $# -gt 0 ]]; do
        case $1 in
            --scenario) SCENARIO="$2"; shift 2 ;;
            --hardware) HARDWARE_MODE="$2"; shift 2 ;;
            --help|-h) parse_args; exit 0 ;;
            *) fatal "Unknown option: $1" ;;
        esac
    done

    [[ ! "$RUN_ID" =~ ^[a-zA-Z0-9_-]+$ ]] && fatal "Invalid run_id: $RUN_ID"
    [[ ! "$DURATION" =~ ^[0-9]+$ ]] || [[ $DURATION -lt 1 ]] && fatal "Duration must be positive integer"
}

# ==================================================================
# Hardware Detection
# ==================================================================
detect_hardware() {
    local platform="unknown"

    [[ -f /etc/nv_tegra_release ]] && platform="jetson"
    lspci 2>/dev/null | grep -qi "semidrive" && platform="semidrive"
    [[ $(uname -m) == "x86_64" ]] && platform="x86_simulation"

    [[ "$HARDWARE_MODE" != "auto" ]] && platform="$HARDWARE_MODE"

    log "Hardware platform: $platform"
    echo "$platform"
}

# ==================================================================
# System Info
# ==================================================================
record_system_info() {
    mkdir -p "$RUN_DIR"
    {
        echo "Experiment: $RUN_ID"
        echo "Date: $(date)"
        echo "Duration: $DURATION"
        echo "Scenario: $SCENARIO"
        echo "Platform: $HARDWARE_PLATFORM"
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "CPU: $(lscpu | awk -F: '/Model name/ {print $2}' | xargs)"
        echo "Cores: $(nproc)"
        echo "Memory: $(free -h | awk '/Mem:/ {print $2}')"
    } > "$RUN_DIR/system_info.txt"
}

# ==================================================================
# LTTng Tracing
# ==================================================================
setup_lttng() {
    LTTNG_SESSION="halo_${RUN_ID}_$(date +%s)"
    local trace_dir="$RUN_DIR/traces"
    mkdir -p "$trace_dir"

    lttng create "$LTTNG_SESSION" --output="$trace_dir" || fatal "LTTng session creation failed"
    if ! lttng enable-event --userspace 'halo_*'; then
        log "Fallback: enabling critical events..."
        for e in halo_camera_frame_received halo_planning_start halo_planning_end halo_control_command_sent halo_brake_actuated halo_npu_inference_start halo_npu_inference_end; do
            lttng enable-event --userspace "$e" || log "Warning: $e not enabled"
        done
    fi

    lttng add-context --userspace --type=vpid || true
    lttng add-context --userspace --type=vtid || true
    lttng add-context --userspace --type=procname || true
    lttng start || fatal "LTTng start failed"
    log "LTTng session started: $LTTNG_SESSION"
}

# ==================================================================
# Run Halo.OS
# ==================================================================
run_halo_os() {
    local halo_bin="$BUILD_DIR/bin/halo_main"
    [[ -x "$halo_bin" ]] || fatal "Halo.OS binary missing"

    local config="$RUN_DIR/halo_config.yaml"
    cat > "$config" << EOF
scenario: $SCENARIO
duration: $DURATION
platform: $HARDWARE_PLATFORM
log_level: info
tracing:
  enabled: true
  lttng_session: $LTTNG_SESSION
output:
  results_dir: $RUN_DIR
EOF

    "$halo_bin" --config="$config" > "$RUN_DIR/halo_stdout.log" 2> "$RUN_DIR/halo_stderr.log" &
    HALO_PID=$!
    sleep 2
    kill -0 "$HALO_PID" 2>/dev/null || fatal "Halo.OS failed to start"
    log "Halo.OS running (PID: $HALO_PID)"
}

# ==================================================================
# Monitor
# ==================================================================
monitor_experiment() {
    local elapsed=0 check_interval=10
    while [[ $elapsed -lt $DURATION ]]; do
        kill -0 "$HALO_PID" 2>/dev/null || fatal "Halo.OS crashed"
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done
    log "Experiment completed: $DURATION seconds"
}

# ==================================================================
# Stop & Collect
# ==================================================================
stop_and_collect() {
    [[ -n "$LTTNG_SESSION" ]] && lttng stop "$LTTNG_SESSION" || true
    [[ -n "$HALO_PID" ]] && kill -TERM "$HALO_PID" 2>/dev/null || true
    sleep 2
    [[ -n "$HALO_PID" ]] && kill -0 "$HALO_PID" 2>/dev/null && kill -KILL "$HALO_PID" 2>/dev/null || true

    local trace_dir="$RUN_DIR/traces"
    local events_file="$RUN_DIR/events.jsonl"
    command -v babeltrace2 >/dev/null && babeltrace2 --output-format=json "$trace_dir" > "$events_file" || log "babeltrace2 missing, skipping trace conversion"

    [[ -n "$LTTNG_SESSION" ]] && lttng destroy "$LTTNG_SESSION" || true
}

# ==================================================================
# Validation
# ==================================================================
validate_results() {
    local errors=0 events_file="$RUN_DIR/events.jsonl"
    [[ ! -f "$events_file" ]] && { log "Events missing"; ((errors++)); }
    [[ ! -s "$RUN_DIR/halo_stdout.log" ]] && { log "Stdout missing"; ((errors++)); }
    [[ -f "$RUN_DIR/halo_stderr.log" ]] && grep -qi "fatal\|critical\|segfault" "$RUN_DIR/halo_stderr.log" && ((errors++))
    [[ $errors -gt 0 ]] && return 1
    log "Validation passed"
}

# ==================================================================
# Main
# ==================================================================
main() {
    parse_args "$@"

    RUN_DIR="$RESULTS_DIR/$RUN_ID"
    [[ -d "$RUN_DIR" ]] && rm -rf "$RUN_DIR"
    mkdir -p "$RUN_DIR"

    HARDWARE_PLATFORM=$(detect_hardware)
    record_system_info
    setup_lttng
    run_halo_os
    monitor_experiment
    stop_and_collect
    validate_results && log "Experiment completed successfully" || fatal "Validation failed"
}

main "$@"
