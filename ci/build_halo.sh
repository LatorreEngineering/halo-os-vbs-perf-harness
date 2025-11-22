#!/usr/bin/env bash
# ci/build_halo.sh
# Build VBSPro (Halo.OS middleware) with LTTng instrumentation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT

HALO_SRC_DIR="${HALO_SRC_DIR:-${PROJECT_ROOT}/halo-os-src}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
LOG_DIR="${PROJECT_ROOT}/logs"

MANIFEST_REPO_URL="${MANIFEST_REPO_URL:-https://gitee.com/haloos/manifests.git}"
MANIFEST_NAME="${MANIFEST_NAME:-vbs.xml}"

CLEAN_BUILD=0
JOBS=$(nproc 2>/dev/null || echo 4)

mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/build_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

fatal() {
    error "$@"
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --clean) CLEAN_BUILD=1; shift ;;
            --jobs) JOBS="$2"; shift 2 ;;
            -j*) JOBS="${1#-j}"; shift ;;
            --help|-h)
                echo "Usage: $0 [--clean] [--jobs N]"
                exit 0
                ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

install_dependencies() {
    log "Installing system dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build git curl ca-certificates \
        openjdk-11-jdk python3 python3-pip \
        lttng-tools liblttng-ust-dev liblttng-ctl-dev liburcu-dev pkg-config
    
    export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-1.11.0-openjdk-amd64}"
    export PATH="$JAVA_HOME/bin:$PATH"
    log "Dependencies installed"
}

install_repo_tool() {
    if command -v repo >/dev/null 2>&1; then
        log "repo tool already installed"
        return 0
    fi
    
    log "Installing repo tool..."
    curl -sSfL https://storage.googleapis.com/git-repo-downloads/repo -o /tmp/repo
    chmod +x /tmp/repo
    sudo mv /tmp/repo /usr/local/bin/repo
    log "repo tool installed"
}

setup_git_auth() {
    if [[ -n "${GITEE_SSH_KEY:-}" ]]; then
        log "Configuring SSH authentication..."
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        echo "$GITEE_SSH_KEY" > ~/.ssh/id_rsa_gitee
        chmod 600 ~/.ssh/id_rsa_gitee
        ssh-keyscan gitee.com >> ~/.ssh/known_hosts 2>/dev/null || true
        cat > ~/.ssh/config << 'SSHCONFIG'
Host gitee.com
    IdentityFile ~/.ssh/id_rsa_gitee
    StrictHostKeyChecking yes
SSHCONFIG
        chmod 600 ~/.ssh/config
        export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa_gitee"
        log "SSH configured"
    elif [[ -n "${GITEE_TOKEN:-}" ]]; then
        log "Using GITEE_TOKEN for authentication"
    fi
}

sync_repository() {
    log "Syncing repository from Gitee..."
    mkdir -p "$HALO_SRC_DIR"
    cd "$HALO_SRC_DIR"
    
    if [[ ! -d ".repo" ]]; then
        log "Initializing repo..."
        local manifest_url="$MANIFEST_REPO_URL"
        
        if [[ -n "${GITEE_TOKEN:-}" ]]; then
            manifest_url="${MANIFEST_REPO_URL/https:\/\//https://${GITEE_TOKEN}@}"
        fi
        
        if [[ -n "${GITEE_SSH_KEY:-}" ]]; then
            manifest_url="${MANIFEST_REPO_URL/https:\/\/gitee.com/git@gitee.com:}"
        fi
        
        repo init -u "$manifest_url" -m "$MANIFEST_NAME" --no-repo-verify || \
            fatal "Failed to initialize repo"
    fi
    
    if [[ -z "${GITEE_SSH_KEY:-}" ]]; then
        log "Normalizing URLs to HTTPS..."
        repo forall -c "
            url=\$(git remote get-url origin 2>/dev/null || true)
            if [[ \"\$url\" == git@* ]]; then
                new_url=\$(echo \"\$url\" | sed 's|git@gitee.com:|https://gitee.com/|')
                git remote set-url origin \"\$new_url\"
            fi
        " 2>/dev/null || true
    fi
    
    local retry=0
    local max_retries=3
    while [[ $retry -lt $max_retries ]]; do
        log "Syncing (attempt $((retry + 1))/${max_retries})..."
        if repo sync -j"$JOBS" --force-sync --no-tags --current-branch; then
            log "Sync successful"
            break
        fi
        ((retry++))
        [[ $retry -lt $max_retries ]] && sleep 5
    done
    
    [[ $retry -ge $max_retries ]] && fatal "Sync failed after $max_retries attempts"
}

record_provenance() {
    log "Recording build provenance..."
    mkdir -p "$BUILD_DIR"
    cd "$HALO_SRC_DIR"
    
    {
        echo "Build Date: $(date)"
        echo "Manifest: $MANIFEST_REPO_URL ($MANIFEST_NAME)"
        echo ""
        repo forall -c "
            echo 'Project: \$REPO_PROJECT'
            echo '  Commit: \$(git rev-parse HEAD 2>/dev/null || echo unknown)'
            echo ''
        " 2>/dev/null || echo "Could not record all states"
    } > "$BUILD_DIR/git_info.txt"
    
    log "Provenance saved"
}

build_idl_tools() {
    local idlgen_dir="$HALO_SRC_DIR/vbs/vbspro/tools/idlgen"
    
    if [[ ! -d "$idlgen_dir" ]]; then
        log "IDL tools not found, skipping"
        return 0
    fi
    
    log "Building IDL tools..."
    cd "$idlgen_dir"
    
    if [[ -f "gradlew" ]]; then
        chmod +x gradlew
        ./gradlew assemble --no-daemon --console=plain 2>&1 | tee -a "$LOG_FILE" || \
            log "Gradle build warnings (non-fatal)"
        log "IDL tools built"
    fi
}

inject_tracepoints() {
    log "Injecting tracepoints..."
    
    local trace_header="$PROJECT_ROOT/tracepoints/halo_tracepoints.h"
    local vbspro_include="$HALO_SRC_DIR/vbs/vbspro/framework/include"
    
    if [[ ! -f "$trace_header" ]]; then
        mkdir -p "$(dirname "$trace_header")"
        cat > "$trace_header" << 'TRACEFILE'
#ifndef HALO_TRACEPOINTS_H
#define HALO_TRACEPOINTS_H

#ifdef ENABLE_LTTNG
#include <lttng/tracepoint.h>

TRACEPOINT_EVENT(halo_vbs, message_send,
    TP_ARGS(const char*, topic, uint64_t, ts, uint32_t, id),
    TP_FIELDS(ctf_string(topic, topic) ctf_integer(uint64_t, ts, ts) ctf_integer(uint32_t, id, id)))

TRACEPOINT_EVENT(halo_vbs, message_recv,
    TP_ARGS(const char*, topic, uint64_t, ts, uint32_t, id),
    TP_FIELDS(ctf_string(topic, topic) ctf_integer(uint64_t, ts, ts) ctf_integer(uint32_t, id, id)))

#else
#define tracepoint(...)
#endif

#endif
TRACEFILE
        log "Created stub tracepoint header"
    fi
    
    mkdir -p "$vbspro_include"
    cp "$trace_header" "$vbspro_include/" 2>/dev/null || true
    log "Tracepoints injected"
}

build_vbspro() {
    log "Building VBSPro..."
    
    local vbspro_dir="$HALO_SRC_DIR/vbs/vbspro"
    [[ ! -d "$vbspro_dir" ]] && fatal "VBSPro not found at: $vbspro_dir"
    
    local cmake_build_dir="$vbspro_dir/build/out"
    [[ $CLEAN_BUILD -eq 1 ]] && rm -rf "$cmake_build_dir"
    
    mkdir -p "$cmake_build_dir"
    cd "$cmake_build_dir"
    
    log "Configuring with CMake..."
    cmake -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_TRACER=ON \
        -DENABLE_TRACING=ON \
        -DENABLE_LTTNG=ON \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install" \
        "$vbspro_dir" || fatal "CMake configuration failed"
    
    log "Building (${JOBS} jobs)..."
    local start_time
    start_time=$(date +%s)
    
    cmake --build . --parallel "$JOBS" || fatal "Build failed"
    
    local end_time
    end_time=$(date +%s)
    log "Build completed in $((end_time - start_time)) seconds"
    
    cmake --install . --prefix "$BUILD_DIR/install" 2>/dev/null || \
        log "Install step warnings (non-fatal)"
}

validate_build() {
    log "Validating build..."
    
    local vbspro_build="$HALO_SRC_DIR/vbs/vbspro/build/out"
    local found=0
    
    if compgen -G "$vbspro_build/*.so" > /dev/null 2>&1; then
        log "Found shared libraries:"
        find "$vbspro_build" -name "*.so" 2>/dev/null | head -3 | while read -r f; do
            log "  - $(basename "$f")"
        done
        ((found++))
    fi
    
    if compgen -G "$vbspro_build/vbs_*" > /dev/null 2>&1; then
        log "Found executables:"
        find "$vbspro_build" -name "vbs_*" -type f 2>/dev/null | head -3 | while read -r f; do
            log "  - $(basename "$f")"
        done
        ((found++))
    fi
    
    [[ $found -eq 0 ]] && log "WARNING: No obvious artifacts found"
    
    cp -r "$vbspro_build"/* "$BUILD_DIR/" 2>/dev/null || true
    log "Artifacts copied to $BUILD_DIR"
}

main() {
    log "========================================"
    log "Halo.OS VBSPro Build Script"
    log "========================================"
    
    parse_args "$@"
    
    log "Configuration:"
    log "  Source: $HALO_SRC_DIR"
    log "  Build: $BUILD_DIR"
    log "  Manifest: $MANIFEST_NAME"
    log "  Jobs: $JOBS"
    
    install_dependencies
    install_repo_tool
    setup_git_auth
    sync_repository
    record_provenance
    build_idl_tools
    inject_tracepoints
    build_vbspro
    validate_build
    
    log "========================================"
    log "Build completed successfully!"
    log "========================================"
    log "Artifacts: $BUILD_DIR/"
    log "Log: $LOG_FILE"
}

main "$@"
