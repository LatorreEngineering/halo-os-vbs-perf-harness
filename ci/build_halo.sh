#!/bin/bash
# ci/build_halo.sh
# Purpose: Sync Halo.OS source from Gitee and build with LTTng instrumentation
# Usage: ./ci/build_halo.sh [--clean] [--jobs N]

set -euo pipefail

# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT

LOG_FILE="${PROJECT_ROOT}/logs/build_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "${PROJECT_ROOT}/logs"

HALO_SRC_DIR="${HALO_SRC_DIR:-${PROJECT_ROOT}/halo-os-src}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
MANIFEST_FILE="${MANIFEST_FILE:-${PROJECT_ROOT}/manifests/pinned_manifest.xml}"

CLEAN_BUILD=0
JOBS=$(nproc 2>/dev/null || echo 4)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log()   { echo "[$(date +'%F %T')] $*" | tee -a "${LOG_FILE}"; }
error() { echo "[$(date +'%F %T')] ERROR: $*" | tee -a "${LOG_FILE}" >&2; }
fatal() { error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Ensure required tools
# ---------------------------------------------------------------------------
log "Installing required system packages..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    git curl python3 libxml2-utils build-essential ninja-build cmake ca-certificates

# ---------------------------------------------------------------------------
# Ensure repo tool exists
# ---------------------------------------------------------------------------
if ! command -v repo >/dev/null 2>&1; then
    log "Installing repo tool..."
    curl -sSfL https://storage.googleapis.com/git-repo-downloads/repo -o repo
    chmod +x repo
    sudo mv repo /usr/local/bin/ || fatal "Failed to install repo tool"
else
    log "Repo tool already installed"
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean) CLEAN_BUILD=1; shift ;;
        --jobs) JOBS="$2"; shift 2 ;;
        -j*) JOBS="${1#-j}"; shift ;;
        *) fatal "Unknown option: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate manifest
# ---------------------------------------------------------------------------
log "Validating manifest: ${MANIFEST_FILE}"
[[ -f "$MANIFEST_FILE" ]] || fatal "Manifest not found"

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$MANIFEST_FILE" || fatal "Malformed XML manifest"
else
    log "Warning: xmllint not available, skipping XML syntax check"
fi

grep -q '<remote' "$MANIFEST_FILE" || fatal "Manifest missing <remote>"
grep -q '<project' "$MANIFEST_FILE" || fatal "Manifest missing <project>"

log "Manifest validation passed"

# ---------------------------------------------------------------------------
# Repo init + sync
# ---------------------------------------------------------------------------
log "Preparing Halo.OS source directory: $HALO_SRC_DIR"
mkdir -p "$HALO_SRC_DIR"
cd "$HALO_SRC_DIR"

if [[ ! -d ".repo" ]]; then
    log "Initializing repo using haloos/manifests.git"
    repo init \
        -u "https://gitee.com/haloos/manifests.git" \
        -m "pinned_manifest.xml" \
        --no-repo-verify || fatal "repo init failed"
else
    log "Repo already initialized"
fi

# Normalize remotes to HTTPS (avoids SSH auth issues)
log "Normalizing remote URLs to HTTPS..."
repo forall -c "git remote set-url origin \$(git config remote.origin.url | sed 's/^git@/https:\\/\\//; s/:/\\//')" || true

# Repo sync with retries
log "Starting repo sync..."
max_retries=3
retry=0
while [[ $retry -lt $max_retries ]]; do
    if repo sync --force-sync --no-clone-bundle -j"$JOBS"; then
        break
    else
        error "Repo sync failed – retrying..."
        ((retry++))
        sleep 5
    fi
done
[[ $retry -lt $max_retries ]] || fatal "Repo sync failed after $max_retries attempts"
log "Repo sync successful"

# ---------------------------------------------------------------------------
# Record git info
# ---------------------------------------------------------------------------
log "Recording git state..."
mkdir -p "$BUILD_DIR"
git_info_file="$BUILD_DIR/git_info.txt"

repo forall -c "echo \"Project: \$REPO_PROJECT\"; echo \"Commit: \$(git rev-parse HEAD)\"; echo \"\"" > "$git_info_file"
log "Git info saved to $git_info_file"

# ---------------------------------------------------------------------------
# Configure Build
# ---------------------------------------------------------------------------
if [[ "$CLEAN_BUILD" -eq 1 ]]; then
    log "Performing clean build..."
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

log "Running CMake configuration..."
cmake -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DENABLE_LTTNG=ON \
    -DENABLE_TRACING=ON \
    -DENABLE_PERF_INSTRUMENTATION=ON \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/install" \
    "$HALO_SRC_DIR" || fatal "CMake configuration failed"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
log "Starting build with $JOBS jobs..."
start_time=$(date +%s)
cmake --build . --parallel "$JOBS" || fatal "Build failed"
end_time=$(date +%s)
log "Build finished in $((end_time - start_time)) seconds"

# ---------------------------------------------------------------------------
# Artifact Validation (strict)
# ---------------------------------------------------------------------------
log "Validating output artifacts..."
declare -a expected_bins=(
    "bin/halo_main"
    "lib/libhalo_core.so"
)

errors=0
for f in "${expected_bins[@]}"; do
    if [[ -f "$f" ]]; then
        log "  + Found: $f"
    else
        error "  - Missing: $f"
        ((errors++))
    fi
done
[[ $errors -eq 0 ]] || fatal "Build validation failed with $errors missing artifacts"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "==============================================="
log "Halo.OS build completed successfully!"
log "Source: $HALO_SRC_DIR"
log "Build:  $BUILD_DIR"
log "Job count: $JOBS"
log "==============================================="
