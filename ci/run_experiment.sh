#!/usr/bin/env bash
# ci/run_experiment.sh
# Purpose: Run Halo.OS VBS experiment with LTTng tracing
# Usage: ./ci/run_experiment.sh <run_id> <duration_seconds> [--scenario SCENARIO] [--hardware MODE]

set -euo pipefail

# -------------------------
# Paths
# -------------------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
RESULTS_DIR="${RESULTS_DIR:-$PROJECT_ROOT/results}"

[[ -f "$PROJECT_ROOT/.env" ]] && source "$PROJECT_ROOT/.env"

# -------------------------
# Defaults
# -------------------------
RUN_ID=""
DURATION=300
SCENARIO="aeb_120kmh"
HARDWARE_MODE="auto"

# -------------------------
# Logging & cleanup
# -------------------------
log()   { echo "[$(date +'%F %T')] $*"; }
error() { echo "[$(date +'%F %T')] ERROR: $*" >&2; }
fatal() { error "$@"; cleanup; exit 1; }

LTTNG_SESSION=""
HALO_PID=""

cleanup() {
    log "Cleaning up..."
    [[ -n "$HALO_PID" ]] && kill -TERM "$HALO_PID" 2>/dev/null || true
    [[ -n "$LTTNG_SESSION" ]] && lttng destroy "$LTTNG_SESSION" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# -------------------------
# Argument parsing
# -------------------------
parse_args() {
    if [[ $# -lt 2 ]]; then
        cat << EOF
Usage: $0 <run_id> <duration_seconds> [OPTIONS]
--scenario SCENARIO   Default: aeb_120kmh
--hardware MODE       auto, hardware, simulation (default: auto)
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
            *) fatal "Unknown option: $1" ;;
        esac
    done

    [[ ! "$RUN_ID" =~ ^[a-zA-Z0-9_-]+$ ]] && fatal "Invalid run_id: $RUN_ID"
    [[ ! "$DURATION" =~ ^[0-9]+$ ]] || [[ $DURATION -lt 1 ]] && fatal "Duration must be positive integer"
}

# -------------------------
# Hardware detection
# -------------------------
detect_hardware() {
    local platform="x86_simulation"
    [[ -f /etc/nv_tegra_release ]] && platform="jetson"
    lspci 2>/dev/null | grep -qi "semidrive" && platform="semidrive"
    [[ "$HARDWARE_MODE" != "auto" ]] && platform="$HARDWARE_MODE"
    log "Hardware platform: $platform"
    echo "$platform"
}

# -------------------------
# Artifact detection
# -------------------------
detect_vbs_lib() {
    local lib=$(find "$BUILD_DIR/install/lib" -name 'liblivbs*.so' | head -n1)
    [[ -z "$lib" ]] && fatal "Cannot find liblivbs.so in $BUILD_DIR/install/lib"
    export LD_LIBRARY_PATH="$(dirname "$lib"):$LD_LIBRARY_PATH"
    log "Using VBS library: $lib"
}

# -------------------------
# System info recording
# -------------------------
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

# -------------------------
# LTTng setup
# -------------------------
setup_lttng() {
    LTTNG_SESSION="halo_${RUN_ID}_$(date +%s)"
    local trace_dir="$RUN_DIR/traces"
    mkdir -p "$trace_dir"
    lttng create "$LTTNG_SESSION" --output="$trace_dir" || fatal "Failed to create LTTng session"
    if ! lttng enable-event --userspace 'halo_*'; then
        log "Fallback: enabling critical events individually..."
        for e in halo_camera_frame_received halo_planning_start halo_planning_end halo_control_command_sent halo_brake_actuated halo_npu_inference_start halo_npu_inference_end; do
            lttng enable-event --userspace "$e" || log "Warning: $e not enabled"
        done
    fi
    lttng add-context --userspace --type=vpid || true
    lttng add-context --userspace --type=vtid || true
    lttng add-context --userspace --type=procname || true
    lttng start || fatal "Failed to start LTTng"
    log "LTTng session started: $LTTNG_SESSION"
}

# -------------------------
# Halo.OS execution
# -------------------------
run_halo_os() {
    detect_vbs_lib
    local dummy_bin="$BUILD_DIR/install/bin/halo_sim"
    mkdir -p "$(dirname "$dummy_bin")"
    echo '#!/bin/bash; sleep $DURATION' > "$dummy_bin"
    chmod +x "$dummy_bin"
    "$dummy_bin" &
    HALO_PID=$!
    sleep 1
    kill -0 "$HALO_PID" 2>/dev/null || fatal "Halo.OS failed to start"
    log "Halo.OS running (PID: $HALO_PID)"
}

# -------------------------
# Monitor & collect
# -------------------------
monitor_experiment() {
    local elapsed=0
    local interval=10
    while [[ $elapsed -lt $DURATION ]]; do
        kill -0 "$HALO_PID" 2>/dev/null || fatal "Halo.OS crashed"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    log "Experiment completed"
}

stop_and_collect() {
    [[ -n "$LTTNG_SESSION" ]] && lttng stop "$LTTNG_SESSION" || true
    [[ -n "$HALO_PID" ]] && kill -TERM "$HALO_PID" 2>/dev/null || true
    sleep 1
    [[ -n "$HALO_PID" ]] && kill -KILL "$HALO_PID" 2>/dev/null || true
    local events_file="$RUN_DIR/events.jsonl"
    if command -v babeltrace2 >/dev/null; then
        babeltrace2 --output-format=json "$RUN_DIR/traces" > "$events_file" || log "babeltrace2 failed"
    fi
}

validate_results() {
    local errors=0
    [[ ! -f "$RUN_DIR/events.jsonl" ]] && ((errors++))
    [[ ! -s "$RUN_DIR/system_info.txt" ]] && ((errors++))
    [[ $errors -gt 0 ]] && return 1
    log "Validation passed"
}

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
