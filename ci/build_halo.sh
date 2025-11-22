#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HALO_SRC="${PROJECT_ROOT}/halo-os-src"
BUILD_DIR="${PROJECT_ROOT}/build"
LOGS_DIR="${PROJECT_ROOT}/logs"

mkdir -p "$LOGS_DIR" "$BUILD_DIR"
exec > >(tee -a "${LOGS_DIR}/build.log") 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
die() { log "ERROR: $1"; exit 1; }

log "Building VBSPro for Halo.OS Perf Harness"

# 1. Repo sync (VBS-focused)
cd "$PROJECT_ROOT"
if [[ ! -d "$HALO_SRC/.repo" ]]; then
    log "Init repo"
    repo init -u "${MANIFEST_REPO_URL:-https://gitee.com/haloos/manifests.git}" -m "${MANIFEST_NAME:-vbs.xml}"
fi
log "Syncing (jobs=$(nproc))"
repo sync -j"$(nproc)" --force-sync || die "Sync failed"

# Provenance (FIXED: Double quotes for expansion)
mkdir -p "$BUILD_DIR"
repo forall -c "echo \"Project: \$REPO_PROJECT | Commit: \$(git rev-parse HEAD)\"" > "${BUILD_DIR}/git_info.txt"

cd "$HALO_SRC"

# 2. Build IDL tools (Gradle, with mirror patch for CI)
VBS_DIR="vbs/vbspro"
if [[ ! -d "$VBS_DIR" ]]; then die "VBSPro not synced"; fi
IDL_DIR="$VBS_DIR/tools/idlgen"
if [[ -f "$IDL_DIR/gradlew" ]]; then
    log "Building IDL tools"
    cd "$IDL_DIR"
    # Patch for faster mirrors
    sed -i 's|services.gradle.org|mirrors.aliyun.com/gradle|g' gradle/wrapper/gradle-wrapper.properties
    ./gradlew assemble --no-daemon || log "IDL build non-fatal"
    cd - >/dev/null
fi

# 3. Instrument LTTng (copy tracepoints)
TRACE_DIR="$PROJECT_ROOT/tracepoints"
if [[ -d "$TRACE_DIR" ]]; then
    log "Instrumenting with tracepoints"
    mkdir -p "$VBS_DIR/framework/include/tracing"
    cp "$TRACE_DIR/"*.h "$VBS_DIR/framework/include/tracing/"
fi

# 4. CMake build in subdir
BUILD_SUB="$VBS_DIR/build/out"
rm -rf "$BUILD_SUB"  # Clean
mkdir -p "$BUILD_SUB"
cd "$BUILD_SUB"

log "CMake configure"
cmake -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install" \
    -DENABLE_TRACER=ON \
    -DLTTNG_ENABLE=ON \
    -DCMAKE_CXX_STANDARD=17 \
    .. || die "CMake failed"

log "Building (jobs=$(nproc))"
ninja -j"$(nproc)" || die "Ninja failed"
ninja install/strip || log "Install non-fatal"

# 5. Smoke test
if [[ -f "$BUILD_DIR/install/lib/liblivbs.so" ]]; then
    log "✅ VBSPro built: liblivbs.so ready for tracing"
else
    die "No liblivbs.so"
fi

log "Build complete. Artifacts in $BUILD_DIR/install"
