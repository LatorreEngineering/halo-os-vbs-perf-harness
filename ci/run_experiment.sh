#!/bin/bash
# ci/run_experiment.sh
# Purpose: Run Halo.OS experiment with LTTng tracing
# Usage: ./ci/run_experiment.sh <run_id> <duration_seconds> [--scenario SCENARIO]

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source environment
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/.env"
fi

BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
RESULTS_DIR="${RESULTS_DIR:-${PROJECT_ROOT}/results}"

# Experiment parameters
RUN_ID=""
DURATION=300  # Default 5 minutes
SCENARIO="aeb_120kmh"
HARDWARE_MODE="auto"  # auto, hardware, simulation

# ==============================================================================
# Logging
# ==============================================================================
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

fatal() {
    error "$@"
    cleanup
    exit 1
}

# ==============================================================================
# Cleanup Handler
# ==============================================================================
LTTNG_SESSION=""
HALO_PID=""

cleanup() {
    log "Cleaning up..."
    
    # Stop Halo.OS if running
    if [[ -n "${HALO_PID}" ]] && kill -0 "${HALO_PID}" 2>/dev/null; then
        log "Stopping Halo.OS (PID: ${HALO_PID})..."
        kill -TERM "${HALO_PID}" 2>/dev/null || true
        
        # Wait for graceful shutdown
        local timeout=10
        while kill -0 "${HALO_PID}" 2>/dev/null && [[ $timeout -gt 0 ]]; do
            sleep 1
            ((timeout--))
        done
        
        # Force kill if still running
        if kill -0 "${HALO_PID}" 2>/dev/null; then
            log "Force killing Halo.OS..."
            kill -KILL "${HALO_PID}" 2>/dev/null || true
        fi
    fi
    
    # Stop LTTng session
    if [[ -n "${LTTNG_SESSION}" ]]; then
        log "Stopping LTTng session: ${LTTNG_SESSION}"
        lttng stop "${LTTNG_SESSION}" 2>/dev/null || true
        lttng destroy "${LTTNG_SESSION}" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

# ==============================================================================
# Argument Parsing
# ==============================================================================
parse_args() {
    if [[ $# -lt 2 ]]; then
        cat << EOF
Usage: $0 <run_id> <duration_seconds> [OPTIONS]

Arguments:
    run_id              Unique identifier for this run (e.g., run001)
    duration_seconds    Experiment duration in seconds

Options:
    --scenario SCENARIO Test scenario (default: aeb_120kmh)
                       Available: aeb_120kmh, lka_80kmh, parking
    --hardware MODE     Hardware mode: auto, hardware, simulation (default: auto)
    --help, -h          Show this help message

Examples:
    $0 run001 300                          # 5-minute AEB test (auto-detect hardware)
    $0 run002 600 --scenario lka_80kmh     # 10-minute LKA test
    $0 run003 120 --hardware simulation    # 2-minute simulation
EOF
        exit 1
    fi
    
    RUN_ID="$1"
    DURATION="$2"
    shift 2
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --scenario)
                SCENARIO="$2"
                shift 2
                ;;
            --hardware)
                HARDWARE_MODE="$2"
                shift 2
                ;;
            --help|-h)
                parse_args  # Will show help and exit
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate run_id
    if [[ ! "${RUN_ID}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        fatal "Invalid run_id: ${RUN_ID}. Use alphanumeric, dash, or underscore."
    fi
    
    # Validate duration
    if [[ ! "${DURATION}" =~ ^[0-9]+$ ]] || [[ ${DURATION} -lt 1 ]]; then
        fatal "Invalid duration: ${DURATION}. Must be positive integer."
    fi
}

# ==============================================================================
# Hardware Detection
# ==============================================================================
detect_hardware() {
    log "Detecting hardware platform..."
    
    local platform="unknown"
    
    # Check for NVIDIA Jetson
    if [[ -f /etc/nv_tegra_release ]]; then
        platform="jetson"
        log "Detected: NVIDIA Jetson"
        
        # Get specific model
        if command -v jetson_release >/dev/null 2>&1; then
            jetson_release | tee -a "${RUN_DIR}/hardware_info.txt"
        fi
    # Check for SemiDrive
    elif lspci 2>/dev/null | grep -qi "semidrive"; then
        platform="semidrive"
        log "Detected: SemiDrive E3650"
    # Check for x86/simulation
    elif [[ $(uname -m) == "x86_64" ]]; then
        platform="x86_simulation"
        log "Detected: x86_64 (simulation mode)"
    fi
    
    # Override if explicitly set
    if [[ "${HARDWARE_MODE}" != "auto" ]]; then
        platform="${HARDWARE_MODE}"
        log "Hardware mode overridden to: ${platform}"
    fi
    
    echo "${platform}"
}

# ==============================================================================
# System Information
# ==============================================================================
record_system_info() {
    log "Recording system information..."
    
    {
        echo "Experiment: ${RUN_ID}"
        echo "Date: $(date)"
        echo "Duration: ${DURATION}s"
        echo "Scenario: ${SCENARIO}"
        echo ""
        echo "System Information"
        echo "=================="
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
        echo "CPU Cores: $(nproc)"
        echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
        echo ""
        echo "Platform: ${HARDWARE_PLATFORM}"
        echo ""
    } > "${RUN_DIR}/system_info.txt"
    
    # Save CPU info
    lscpu > "${RUN_DIR}/cpuinfo.txt" 2>&1 || true
    
    # Save memory info
    free -h > "${RUN_DIR}/meminfo.txt" 2>&1 || true
    
    # Save kernel parameters
    sysctl -a > "${RUN_DIR}/sysctl.txt" 2>&1 || true
}

# ==============================================================================
# LTTng Setup
# ==============================================================================
setup_lttng() {
    log "Setting up LTTng tracing..."
    
    LTTNG_SESSION="halo_${RUN_ID}_$(date +%s)"
    
    # Create session with output to run directory
    local trace_dir="${RUN_DIR}/traces"
    mkdir -p "${trace_dir}"
    
    if ! lttng create "${LTTNG_SESSION}" --output="${trace_dir}"; then
        fatal "Failed to create LTTng session"
    fi
    
    log "Created LTTng session: ${LTTNG_SESSION}"
    
    # Enable userspace events for Halo.OS
    # Using wildcard to catch all halo tracepoints
    if ! lttng enable-event --userspace 'halo_*'; then
        error "Warning: Failed to enable halo_* events. Trying specific events..."
        
        # Enable specific critical events
        local events=(
            "halo_camera_frame_received"
            "halo_planning_start"
            "halo_planning_end"
            "halo_control_command_sent"
            "halo_brake_actuated"
            "halo_npu_inference_start"
            "halo_npu_inference_end"
        )
        
        for event in "${events[@]}"; do
            lttng enable-event --userspace "${event}" || \
                error "Warning: Failed to enable ${event}"
        done
    fi
    
    # Add context information for better correlation
    lttng add-context --userspace --type=vpid || true
    lttng add-context --userspace --type=vtid || true
    lttng add-context --userspace --type=procname || true
    
    # Start tracing
    if ! lttng start; then
        fatal "Failed to start LTTng session"
    fi
    
    log "LTTng tracing started"
}

# ==============================================================================
# Run Halo.OS
# ==============================================================================
run_halo_os() {
    log "Starting Halo.OS..."
    
    local halo_bin="${BUILD_DIR}/bin/halo_main"
    
    if [[ ! -x "${halo_bin}" ]]; then
        fatal "Halo.OS binary not found or not executable: ${halo_bin}"
    fi
    
    # Prepare configuration
    local config_file="${RUN_DIR}/halo_config.yaml"
    cat > "${config_file}" << EOF
scenario: ${SCENARIO}
duration: ${DURATION}
platform: ${HARDWARE_PLATFORM}
log_level: info
tracing:
  enabled: true
  lttng_session: ${LTTNG_SESSION}
output:
  results_dir: ${RUN_DIR}
EOF
    
    # Start Halo.OS in background
    log "Launching Halo.OS with config: ${config_file}"
    
    # Redirect stdout/stderr to log files
    "${halo_bin}" --config="${config_file}" \
        > "${RUN_DIR}/halo_stdout.log" \
        2> "${RUN_DIR}/halo_stderr.log" &
    
    HALO_PID=$!
    
    log "Halo.OS started (PID: ${HALO_PID})"
    
    # Verify process started successfully
    sleep 2
    if ! kill -0 "${HALO_PID}" 2>/dev/null; then
        error "Halo.OS process died immediately"
        cat "${RUN_DIR}/halo_stderr.log"
        fatal "Failed to start Halo.OS"
    fi
}

# ==============================================================================
# Monitor Experiment
# ==============================================================================
monitor_experiment() {
    log "Monitoring experiment for ${DURATION} seconds..."
    
    local elapsed=0
    local check_interval=10
    local last_log=0
    
    while [[ ${elapsed} -lt ${DURATION} ]]; do
        # Check if Halo.OS is still running
        if ! kill -0 "${HALO_PID}" 2>/dev/null; then
            error "Halo.OS process terminated unexpectedly"
            cat "${RUN_DIR}/halo_stderr.log"
            fatal "Experiment failed - Halo.OS crashed"
        fi
        
        # Log progress every 30 seconds
        if [[ $((elapsed - last_log)) -ge 30 ]]; then
            log "Progress: ${elapsed}/${DURATION} seconds ($(( (elapsed * 100) / DURATION ))%)"
            last_log=${elapsed}
        fi
        
        sleep ${check_interval}
        elapsed=$((elapsed + check_interval))
    done
    
    log "Experiment duration completed"
}

# ==============================================================================
# Stop and Collect Data
# ==============================================================================
stop_and_collect() {
    log "Stopping experiment and collecting data..."
    
    # Stop LTTng first to ensure all events are captured
    if [[ -n "${LTTNG_SESSION}" ]]; then
        lttng stop "${LTTNG_SESSION}"
        log "LTTng tracing stopped"
    fi
    
    # Gracefully stop Halo.OS
    if [[ -n "${HALO_PID}" ]] && kill -0 "${HALO_PID}" 2>/dev/null; then
        log "Sending SIGTERM to Halo.OS..."
        kill -TERM "${HALO_PID}"
        
        # Wait for graceful shutdown
        local timeout=30
        while kill -0 "${HALO_PID}" 2>/dev/null && [[ $timeout -gt 0 ]]; do
            sleep 1
            ((timeout--))
        done
        
        if kill -0 "${HALO_PID}" 2>/dev/null; then
            log "Halo.OS did not stop gracefully, force killing..."
            kill -KILL "${HALO_PID}" || true
        else
            log "Halo.OS stopped gracefully"
        fi
    fi
    
    # Convert LTTng traces to text format for easier analysis
    log "Converting LTTng traces..."
    local trace_dir="${RUN_DIR}/traces"
    local events_file="${RUN_DIR}/events.jsonl"
    
    if command -v babeltrace2 >/dev/null 2>&1; then
        babeltrace2 --output-format=json "${trace_dir}" > "${events_file}" || \
            error "Failed to convert traces with babeltrace2"
    else
        error "Warning: babeltrace2 not installed, skipping trace conversion"
    fi
    
    # Destroy LTTng session
    if [[ -n "${LTTNG_SESSION}" ]]; then
        lttng destroy "${LTTNG_SESSION}" || true
        LTTNG_SESSION=""
    fi
}

# ==============================================================================
# Validation
# ==============================================================================
validate_results() {
    log "Validating experiment results..."
    
    local errors=0
    
    # Check for events file
    local events_file="${RUN_DIR}/events.jsonl"
    if [[ ! -f "${events_file}" ]]; then
        error "Events file not found: ${events_file}"
        ((errors++))
    else
        # Check file is not empty
        local line_count
        line_count=$(wc -l < "${events_file}" || echo 0)
        
        if [[ ${line_count} -eq 0 ]]; then
            error "Events file is empty - no trace data collected"
            ((errors++))
        else
            log "Collected ${line_count} trace events"
        fi
    fi
    
    # Check for log files
    if [[ ! -s "${RUN_DIR}/halo_stdout.log" ]]; then
        error "Halo.OS stdout log is empty or missing"
        ((errors++))
    fi
    
    # Check for critical errors in stderr
    if [[ -f "${RUN_DIR}/halo_stderr.log" ]]; then
        if grep -qi "fatal\|critical\|segfault" "${RUN_DIR}/halo_stderr.log"; then
            error "Critical errors found in Halo.OS stderr"
            ((errors++))
        fi
    fi
    
    if [[ ${errors} -gt 0 ]]; then
        error "Validation found ${errors} issue(s)"
        return 1
    fi
    
    log "Validation passed"
    return 0
}

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    log "========================================"
    log "Halo.OS Experiment Execution"
    log "========================================"
    
    parse_args "$@"
    
    # Create run directory
    RUN_DIR="${RESULTS_DIR}/${RUN_ID}"
    if [[ -d "${RUN_DIR}" ]]; then
        error "Run directory already exists: ${RUN_DIR}"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            fatal "Aborted by user"
        fi
        rm -rf "${RUN_DIR}"
    fi
    mkdir -p "${RUN_DIR}"
    
    log "Run directory: ${RUN_DIR}"
    
    # Detect hardware
    HARDWARE_PLATFORM=$(detect_hardware)
    export HARDWARE_PLATFORM
    
    # Record system info
    record_system_info
    
    # Setup tracing
    setup_lttng
    
    # Run experiment
    run_halo_os
    monitor_experiment
    stop_and_collect
    
    # Validate
    if validate_results; then
        log "========================================"
        log "Experiment completed successfully!"
        log "========================================"
        log "Results saved to: ${RUN_DIR}"
        log "Next step: python3 ci/analyze_vbs.py ${RUN_DIR}/events.jsonl"
        exit 0
    else
        error "Experiment completed with validation errors"
        exit 1
    fi
}

main "$@"
