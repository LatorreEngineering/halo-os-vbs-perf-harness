#!/bin/bash
# ci/build_halo.sh
# Purpose: Sync Halo.OS source and build with LTTng instrumentation
# Usage: ./ci/build_halo.sh [--clean] [--jobs N]

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_FILE="${PROJECT_ROOT}/logs/build_$(date +%Y%m%d_%H%M%S).log"

# Source environment if available
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/.env"
fi

# Default values
HALO_SRC_DIR="${HALO_SRC_DIR:-${PROJECT_ROOT}/halo-os-src}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
MANIFEST_DIR="${PROJECT_ROOT}/manifests"
CLEAN_BUILD=0
JOBS=$(nproc 2>/dev/null || echo 4)

# ==============================================================================
# Logging
# ==============================================================================
mkdir -p "$(dirname "${LOG_FILE}")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

fatal() {
    error "$@"
    exit 1
}

# ==============================================================================
# Argument Parsing
# ==============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                CLEAN_BUILD=1
                shift
                ;;
            --jobs)
                JOBS="$2"
                shift 2
                ;;
            -j*)
                JOBS="${1#-j}"
                shift
                ;;
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

Options:
    --clean         Perform clean build (remove build directory)
    --jobs N, -jN   Number of parallel build jobs (default: ${JOBS})
    --help, -h      Show this help message

Environment Variables:
    HALO_SRC_DIR    Source directory (default: ${HALO_SRC_DIR})
    BUILD_DIR       Build directory (default: ${BUILD_DIR})
    CMAKE_BUILD_TYPE Build type (default: RelWithDebInfo)
EOF
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# Manifest Validation
# ==============================================================================
validate_manifest() {
    log "Validating manifest..."
    
    local manifest="${MANIFEST_DIR}/pinned_manifest.xml"
    
    if [[ ! -f "${manifest}" ]]; then
        fatal "Manifest not found: ${manifest}"
    fi
    
    # Validate XML syntax
    if command -v xmllint >/dev/null 2>&1; then
        if ! xmllint --noout "${manifest}" 2>/dev/null; then
            fatal "Invalid XML in manifest: ${manifest}"
        fi
        log "Manifest XML is valid"
    else
        log "Warning: xmllint not available, skipping XML validation"
    fi
    
    # Check for required elements
    if ! grep -q '<remote' "${manifest}"; then
        fatal "Manifest missing <remote> elements"
    fi
    
    if ! grep -q '<project' "${manifest}"; then
        fatal "Manifest missing <project> elements"
    fi
    
    log "Manifest validation passed: ${manifest}"
}

# ==============================================================================
# Repository Sync
# ==============================================================================
sync_repository() {
    log "Syncing Halo.OS repository..."
    
    local manifest="${MANIFEST_DIR}/pinned_manifest.xml"
    
    # Create source directory if needed
    mkdir -p "${HALO_SRC_DIR}"
    cd "${HALO_SRC_DIR}"
    
    # Initialize repo if not already done
    if [[ ! -d .repo ]]; then
        log "Initializing repo..."
        repo init -u "${PROJECT_ROOT}" -m "manifests/pinned_manifest.xml" || \
            fatal "Failed to initialize repo"
    else
        log "Repo already initialized"
    fi
    
    # Sync with retries
    local max_retries=3
    local retry=0
    local sync_success=0
    
    while [[ ${retry} -lt ${max_retries} ]]; do
        log "Syncing repositories (attempt $((retry + 1))/${max_retries})..."
        
        # Use --force-sync to handle detached heads
        # Use --current-branch to only sync the current branch
        # Use --no-tags to skip tags for faster sync
        if repo sync --force-sync --current-branch --no-tags -j"${JOBS}"; then
            sync_success=1
            break
        else
            error "Sync attempt $((retry + 1)) failed"
            ((retry++))
            sleep 5
        fi
    done
    
    if [[ ${sync_success} -eq 0 ]]; then
        fatal "Failed to sync repository after ${max_retries} attempts"
    fi
    
    log "Repository sync completed successfully"
    
    # Verify critical directories exist
    local critical_dirs=("core" "drivers" "services")
    for dir in "${critical_dirs[@]}"; do
        if [[ ! -d "${HALO_SRC_DIR}/${dir}" ]]; then
            error "Warning: Expected directory not found: ${dir}"
        fi
    done
}

# ==============================================================================
# Git Commit Info
# ==============================================================================
record_git_info() {
    log "Recording git commit information..."
    
    local info_file="${BUILD_DIR}/git_info.txt"
    mkdir -p "${BUILD_DIR}"
    
    {
        echo "Build Date: $(date)"
        echo "Manifest: ${MANIFEST_DIR}/pinned_manifest.xml"
        echo ""
        echo "Repository States:"
        echo "===================="
        
        # Record state of all projects
        cd "${HALO_SRC_DIR}"
        repo forall -c 'echo "Project: $REPO_PROJECT"; echo "  Path: $REPO_PATH"; echo "  Commit: $(git rev-parse HEAD)"; echo "  Branch: $(git rev-parse --abbrev-ref HEAD)"; echo ""'
    } > "${info_file}"
    
    log "Git information saved to ${info_file}"
}

# ==============================================================================
# CMake Configuration
# ==============================================================================
configure_build() {
    log "Configuring build with CMake..."
    
    # Clean build if requested
    if [[ ${CLEAN_BUILD} -eq 1 ]]; then
        log "Performing clean build..."
        rm -rf "${BUILD_DIR}"
        mkdir -p "${BUILD_DIR}"
    else
        mkdir -p "${BUILD_DIR}"
    fi
    
    cd "${BUILD_DIR}"
    
    # CMake configuration
    local cmake_args=(
        -G "${CMAKE_GENERATOR:-Ninja}"
        -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-RelWithDebInfo}"
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
        -DENABLE_LTTNG=ON
        -DENABLE_TRACING=ON
        -DENABLE_PERF_INSTRUMENTATION=ON
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/install"
    )
    
    # Add debug symbols but keep optimizations for realistic performance
    cmake_args+=(
        -DCMAKE_C_FLAGS_RELWITHDEBINFO="-O2 -g -DNDEBUG"
        -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-O2 -g -DNDEBUG"
    )
    
    log "CMake command: cmake ${cmake_args[*]} ${HALO_SRC_DIR}"
    
    if ! cmake "${cmake_args[@]}" "${HALO_SRC_DIR}"; then
        fatal "CMake configuration failed"
    fi
    
    log "CMake configuration completed successfully"
}

# ==============================================================================
# Build
# ==============================================================================
build_project() {
    log "Building project with ${JOBS} parallel jobs..."
    
    cd "${BUILD_DIR}"
    
    local build_start
    build_start=$(date +%s)
    
    # Build with progress output
    if ! cmake --build . --parallel "${JOBS}" --target all; then
        error "Build failed"
        
        # Try to provide helpful error context
        if [[ -f "CMakeFiles/CMakeError.log" ]]; then
            error "CMake error log (last 20 lines):"
            tail -20 "CMakeFiles/CMakeError.log" | tee -a "${LOG_FILE}"
        fi
        
        fatal "Build failed - see log for details"
    fi
    
    local build_end
    build_end=$(date +%s)
    local build_time=$((build_end - build_start))
    
    log "Build completed in ${build_time} seconds"
}

# ==============================================================================
# Build Validation
# ==============================================================================
validate_build() {
    log "Validating build artifacts..."
    
    cd "${BUILD_DIR}"
    
    local errors=0
    
    # Expected executables/libraries (adjust based on actual project)
    local expected_artifacts=(
        "bin/halo_main"
        "bin/camera_service"
        "bin/planning_service"
        "bin/control_service"
        "lib/libhalo_core.so"
    )
    
    for artifact in "${expected_artifacts[@]}"; do
        if [[ ! -f "${artifact}" ]]; then
            error "Expected artifact not found: ${artifact}"
            ((errors++))
        else
            log "Found artifact: ${artifact}"
            
            # Check for LTTng symbols
            if command -v nm >/dev/null 2>&1; then
                if nm "${artifact}" 2>/dev/null | grep -q lttng; then
                    log "  ✓ LTTng instrumentation detected"
                else
                    error "  ✗ LTTng instrumentation NOT detected"
                    ((errors++))
                fi
            fi
        fi
    done
    
    if [[ ${errors} -gt 0 ]]; then
        fatal "Build validation failed with ${errors} error(s)"
    fi
    
    log "Build validation passed - all artifacts present and instrumented"
}

# ==============================================================================
# Build Summary
# ==============================================================================
print_summary() {
    log ""
    log "========================================"
    log "Build Summary"
    log "========================================"
    log "Source directory:  ${HALO_SRC_DIR}"
    log "Build directory:   ${BUILD_DIR}"
    log "Build type:        ${CMAKE_BUILD_TYPE:-RelWithDebInfo}"
    log "Parallel jobs:     ${JOBS}"
    log "Clean build:       ${CLEAN_BUILD}"
    log "========================================"
    log ""
    log "Build artifacts ready for testing"
    log "Next step: ./ci/run_experiment.sh"
}

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    log "========================================"
    log "Halo.OS Build Script"
    log "========================================"
    
    parse_args "$@"
    
    # Verify prerequisites
    if ! command -v repo >/dev/null 2>&1; then
        fatal "repo tool not found. Run ./ci/setup_env.sh first"
    fi
    
    if ! command -v cmake >/dev/null 2>&1; then
        fatal "cmake not found. Run ./ci/setup_env.sh first"
    fi
    
    validate_manifest
    sync_repository
    record_git_info
    configure_build
    build_project
    validate_build
    print_summary
    
    log "Build completed successfully!"
}

main "$@"
