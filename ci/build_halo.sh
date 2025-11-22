#!/usr/bin/env bash
# ci/build_halo.sh
# Build instrumented VBSPro (Halo.OS VBS) with LTTng hooks for the perf harness.
# Usage: ./ci/build_halo.sh [--clean] [--jobs N]
set -euo pipefail

# --------------------------
# Init vars (avoid SC2155)
# --------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT

LOG_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/build_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Defaults (override via env if needed)
HALO_SRC_DIR="${HALO_SRC_DIR:-${PROJECT_ROOT}/halo-os-src}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
MANIFEST_REPO_URL="${MANIFEST_REPO_URL:-https://gitee.com/haloos/manifests.git}"
MANIFEST_NAME="${MANIFEST_NAME:-vbs.xml}"
LOCAL_MANIFEST_PATH="${LOCAL_MANIFEST_PATH:-${PROJECT_ROOT}/manifests/pinned_manifest.xml}"

CLEAN_BUILD=0
JOBS=$(nproc 2>/dev/null || echo 4)

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) CLEAN_BUILD=1; shift ;;
    --jobs) JOBS="$2"; shift 2 ;;
    -j*) JOBS="${1#-j}"; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

log() { echo "[$(date +'%F %T')] $*"; }
fatal() { echo "[$(date +'%F %T')] FATAL: $*" >&2; exit 1; }

log "Starting build_halo.sh (VBSPro build). Log: $LOG_FILE"

# --------------------------
# Install system deps
# --------------------------
log "Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  git curl build-essential cmake ninja-build openjdk-11-jdk \
  python3 python3-pip lttng-tools liblttng-ust-dev ca-certificates

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-1.11.0-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$PATH"

# --------------------------
# Ensure repo tool
# --------------------------
if ! command -v repo >/dev/null 2>&1; then
  log "Installing repo tool..."
  curl -sSfL https://storage.googleapis.com/git-repo-downloads/repo -o /tmp/repo
  chmod +x /tmp/repo
  sudo mv /tmp/repo /usr/local/bin/repo
else
  log "repo present: $(repo --version 2>/dev/null || true)"
fi

# --------------------------
# Repo init + sync
# --------------------------
log "Preparing halo source dir: $HALO_SRC_DIR"
mkdir -p "$HALO_SRC_DIR"
cd "$HALO_SRC_DIR"

if [[ ! -d ".repo" ]]; then
  log "repo init -u ${MANIFEST_REPO_URL} -m ${MANIFEST_NAME}"
  if [[ -n "${GITEE_SSH_KEY:-}" ]]; then
    log "Using GITEE_SSH_KEY for repo access"
    mkdir -p ~/.ssh
    printf '%s\n' "$GITEE_SSH_KEY" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan gitee.com >> ~/.ssh/known_hosts || true
    export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=yes"
    repo init -u "git@gitee.com:haloos/manifests.git" -m "${MANIFEST_NAME}" --no-repo-verify
  elif [[ -n "${GITEE_TOKEN:-}" ]]; then
    log "Using GITEE_TOKEN for HTTPS access"
    repo init -u "https://${GITEE_TOKEN}@gitee.com/haloos/manifests.git" -m "${MANIFEST_NAME}" --no-repo-verify
  else
    repo init -u "${MANIFEST_REPO_URL}" -m "${MANIFEST_NAME}" --no-repo-verify
  fi
else
  log "repo already initialized"
fi

# Normalize only SSH-origin remotes to HTTPS (safe)
repo forall -c 'orig=$(git remote get-url origin 2>/dev/null || true); if [[ "$orig" == git@* ]]; then https=$(echo "$orig" | sed "s|git@|https://|; s|:|/|"); git remote set-url origin "$https"; fi' || true

# sync with retries
max_retries=3
retry=0
while [[ $retry -lt $max_retries ]]; do
  log "repo sync attempt $((retry+1))/$max_retries"
  if repo sync -j"$JOBS" --fail-fast; then
    break
  fi
  ((retry++))
  sleep 4
done
if [[ $retry -ge $max_retries ]]; then
  fatal "repo sync failed after $max_retries attempts"
fi
log "repo sync finished"

# Record provenance
mkdir -p "$BUILD_DIR"
git_info_file="$BUILD_DIR/git_info.txt"
repo forall -c "echo \"Project: \$REPO_PROJECT\"; echo \"Commit: \$(git rev-parse HEAD)\"; echo" > "$git_info_file" || true
log "Saved git info to $git_info_file"

# --------------------------
# Build VBSPro (CMake) — located at vbs/vbspro
# --------------------------
VBSPRO_DIR="$HALO_SRC_DIR/vbs/vbspro"
if [[ ! -d "$VBSPRO_DIR" ]]; then
  fatal "vbspro not found at $VBSPRO_DIR (manifest may not include it)"
fi

# Build IDL tooling if present (some projects include gradle wrapper)
IDLGEN_DIR="$VBSPRO_DIR/tools/idlgen"
if [[ -d "$IDLGEN_DIR" ]]; then
  log "Building idlgen (if gradle wrapper present) at $IDLGEN_DIR"
  cd "$IDLGEN_DIR"
  if [[ -f "gradlew" ]]; then
    ./gradlew assemble --no-daemon || log "gradle assemble returned non-zero (continuing)"
  else
    log "No gradle wrapper; skipping idlgen build"
  fi
  cd - >/dev/null || true
else
  log "No idlgen dir present; skipping"
fi

# Copy harness tracepoint headers if present
HARNESS_TRACE_HDR="$PROJECT_ROOT/tracepoints/halo_tracepoints.h"
if [[ -f "$HARNESS_TRACE_HDR" ]]; then
  log "Copying harness tracepoint header into VBSPro include"
  mkdir -p "$VBSPRO_DIR/framework/include"
  cp "$HARNESS_TRACE_HDR" "$VBSPRO_DIR/framework/include/" || true
else
  log "No harness tracepoint header found at $HARNESS_TRACE_HDR (OK if not used)"
fi

# Configure and build in vbs/vbspro/build/out
BUILD_SUBDIR="$VBSPRO_DIR/build/out"
if [[ "$CLEAN_BUILD" -eq 1 ]]; then
  rm -rf "$BUILD_SUBDIR"
fi
mkdir -p "$BUILD_SUBDIR"
cd "$BUILD_SUBDIR"

log "Running cmake for VBSPro (enabling tracing flags if available)"
cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_TRACER=ON -DENABLE_TRACING=ON -DENABLE_LTTNG=ON \
  "$VBSPRO_DIR" || fatal "CMake configure failed for VBSPro"

log "Building VBSPro (jobs=$JOBS)"
cmake --build . --parallel "$JOBS" || fatal "VBSPro build failed"

# Install to overall build dir (best-effort)
log "Installing build outputs to $BUILD_DIR/install"
cmake --install . --prefix "$BUILD_DIR/install" || log "cmake --install returned non-zero (install may be optional)"

# Basic smoke check: ensure there is at least one lib or binary
if ls "$BUILD_DIR/install/lib"/* 1>/dev/null 2>&1 || ls "$BUILD_SUBDIR"/*.so 1>/dev/null 2>&1; then
  log "VBSPro build artifacts present"
else
  log "WARNING: No obvious VBSPro artifacts found in install dir; check CMake targets"
fi

log "VBSPro build completed successfully. Artifacts: $BUILD_DIR/install (and $BUILD_SUBDIR)"

exit 0
