#!/bin/bash
# ci/build_halo.sh
# Purpose: Sync Halo.OS source from Gitee and build with LTTng instrumentation
# Usage: ./ci/build_halo.sh [--clean] [--jobs N]

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_FILE="${PROJECT_ROOT}/logs/build_$(date +%Y%m%d_%H%M%S).log"

# Load environment if available
[[ -f "${PROJECT_ROOT}/.env" ]] && source "${PROJECT_ROOT}/.env"

# Default directories and parameters
HALO_SRC_DIR="${HALO_SRC_DIR:-${PROJECT_ROOT}/halo-os-src}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
MANIFEST_FILE="${MANIFEST_FILE:-${PROJECT_ROOT}/manifests/pinned_manifest.xml}"
CLEAN_BUILD=0
JOBS=$(nproc 2>/dev/null || echo 4)

mkdir -p "$(dirname "${LOG_FILE}")"

log() { echo "[$(date +'%F %T')] $*" | tee -a "${LOG_FILE}"; }
error() { echo "[$(date +'%F %T')] ERROR: $*" | tee -a "${LOG_FILE}" >&2; }
fatal() { error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean) CLEAN_BUILD=1; shift ;;
        --jobs) JOBS="$2"; shift 2 ;;
        -j*) JOBS="${1#-j}"; shift ;;
        --help|-h)
            cat << EOF
Usage: $0 [OPTIONS]
Options:
  --clean           Perform clean build
  --jobs N, -jN     Parallel build jobs (default: $JOBS)
Environment Variables:
  HALO_SRC_DIR      Source directory
  BUILD_DIR         Build directory
  MANIFEST_FILE     Manifest file path
EOF
            exit 0
            ;;
        *) fatal "Unknown option: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate manifest
# ---------------------------------------------------------------------------
log "Validating manifest: ${MANIFEST_FILE}"
[[ -f "$MANIFEST_FILE" ]] || fatal "Manifest not found"

command -v xmllint >/dev/null 2>&1 && xmllint --noout "$MANIFEST_FILE" || log "Warning: xmllint not available"

grep -q '<remote' "$MANIFEST_FILE" || fatal "Manifest missing <remote>"
grep -q '<project' "$MANIFEST_FILE" || fatal "Manifest missing <project>"

log "Manifest validation passed"

# ---------------------------------------------------------------------------
# Repo sync
# ---------------------------------------------------------------------------
log "Syncing Halo.OS from Gitee..."
mkdir -p "$HALO_SRC_DIR"
cd "$HALO_SRC_DIR"

if [[ ! -d .repo ]]; then
    log "Initializing repo..."
    repo init -u "https://gitee.com/LatorreEngineering/halo-os-vbs-perf-harness" -m "$MANIFEST_FILE" || \
        fatal "Repo init failed"
else
    log "Repo already initialized"
fi

max_retries=3
retry=0
while [[ $retry -lt $max_retries ]]; do
    log "Repo sync attempt $((retry + 1))/$max_retries"
    if repo sync --force-sync --current-branch --no-tags -j"$JOBS"; then
        break
    else
        error "Sync failed"
        ((retry++))
        sleep 5
    fi
done
[[ $retry -lt $max_retries ]] || fatal "Repo sync failed after $max_retries attempts"
log "Repo sync successful"

# ---------------------------------------------------------------------------
# Record git info
# ---------------------------------------------------------------------------
log "Recording git info..."
mkdir -p "$BUILD_DIR"
git_info_file="${BUILD_DIR}/git_info.txt"
repo forall -c 'echo "Project: $REPO_PROJECT"; echo "Commit: $(git rev-parse HEAD)"; echo "Branch: $(git rev-parse --abbrev-ref HEAD)"; echo ""' > "$git_info_file"
log "Git info saved to $git_info_file"

# ---------------------------------------------------------------------------
# Configure build
# ---------------------------------------------------------------------------
log "Configuring build..."
[[ $CLEAN_BUILD -eq 1 ]] && rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake_args=(
    -G "${CMAKE_GENERATOR:-Ninja}"
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-RelWithDebInfo}"
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    -DENABLE_LTTNG=ON
    -DENABLE_TRACING=ON
    -DENABLE_PERF_INSTRUMENTATION=ON
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/install"
)

log "CMake: cmake ${cmake_args[*]} $HALO_SRC_DIR"
cmake "${cmake_args[@]}" "$HALO_SRC_DIR" || fatal "CMake configuration failed"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
log "Building project with $JOBS jobs..."
start_time=$(date +%s)
cmake --build . --parallel "$JOBS" --target all || fatal "Build failed"
end_time=$(date +%s)
log "Build completed in $((end_time - start_time)) seconds"

# ---------------------------------------------------------------------------
# Validate build artifacts
# ---------------------------------------------------------------------------
log "Validating build artifacts..."
expected_artifacts=(
    "bin/halo_main"
    "bin/camera_service"
    "bin/planning_service"
    "bin/control_service"
    "lib/libhalo_core.so"
)

errors=0
for artifact in "${expected_artifacts[@]}"; do
    if [[ ! -f "$artifact" ]]; then
        error "Missing artifact: $artifact"
        ((errors++))
    else
        log "Found: $artifact"
        command -v nm >/dev/null 2>&1 && nm "$artifact" 2>/dev/null | grep -q lttng && log "  ✓ LTTng OK" || log "  ✗ LTTng missing"
    fi
done
[[ $errors -eq 0 ]] || fatal "Build validation failed with $errors errors"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "===================================="
log "Halo.OS build completed successfully!"
log "Source: $HALO_SRC_DIR"
log "Build:  $BUILD_DIR"
log "Jobs:   $JOBS"
log "Artifacts validated and ready for experiments"
log "===================================="
