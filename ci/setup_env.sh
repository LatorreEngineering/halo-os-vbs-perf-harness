#!/bin/bash
# ci/setup_env.sh
# Purpose: Install and validate all dependencies for Halo.OS performance testing
# Usage: ./ci/setup_env.sh

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ==============================================================================
# Configuration
# ==============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_FILE="${PROJECT_ROOT}/setup.log"
readonly PYTHON_MIN_VERSION="3.10"
readonly REPO_TOOL_VERSION="2.41"

# ==============================================================================
# Logging Functions
# ==============================================================================
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
# Environment Detection
# ==============================================================================
detect_environment() {
    log "Detecting environment..."
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID}"
        log "Detected OS: ${OS_ID} ${OS_VERSION}"
    else
        fatal "Cannot detect OS. /etc/os-release not found."
    fi
    
    # Validate supported OS
    case "${OS_ID}" in
        ubuntu)
            if [[ "${OS_VERSION}" != "22.04" ]]; then
                error "Warning: Ubuntu 22.04 LTS is recommended. Detected: ${OS_VERSION}"
            fi
            ;;
        *)
            error "Warning: ${OS_ID} is not officially supported. Proceed with caution."
            ;;
    esac
    
    # Detect if running in CI
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        export RUNNING_IN_CI=1
        log "Running in CI environment"
    else
        export RUNNING_IN_CI=0
        log "Running in local development environment"
    fi
    
    # Detect if running in Docker
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        export RUNNING_IN_DOCKER=1
        log "Running inside Docker container"
    else
        export RUNNING_IN_DOCKER=0
    fi
}

# ==============================================================================
# Dependency Installation
# ==============================================================================
install_system_dependencies() {
    log "Installing system dependencies..."
    
    # Check if we need sudo
    if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        SUDO=""
    fi
    
    # Update package lists
    ${SUDO} apt-get update || fatal "Failed to update package lists"
    
    # Install build essentials
    local packages=(
        build-essential
        cmake
        ninja-build
        git
        curl
        wget
        python3
        python3-pip
        python3-venv
        lttng-tools
        lttng-modules-dkms
        liblttng-ust-dev
        liblttng-ctl-dev
        liburcu-dev
        pkg-config
        repo
    )
    
    log "Installing packages: ${packages[*]}"
    ${SUDO} apt-get install -y "${packages[@]}" || fatal "Failed to install system packages"
    
    log "System dependencies installed successfully"
}

# ==============================================================================
# Python Environment Setup
# ==============================================================================
setup_python_environment() {
    log "Setting up Python environment..."
    
    # Verify Python version
    if ! command -v python3 >/dev/null 2>&1; then
        fatal "python3 not found. Please install Python 3.10 or newer."
    fi
    
    local python_version
    python_version=$(python3 --version | awk '{print $2}')
    log "Detected Python version: ${python_version}"
    
    # Check minimum version
    if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 10) else 1)"; then
        fatal "Python ${PYTHON_MIN_VERSION} or newer is required. Found: ${python_version}"
    fi
    
    # Create virtual environment if it doesn't exist
    local venv_dir="${PROJECT_ROOT}/venv"
    if [[ ! -d "${venv_dir}" ]]; then
        log "Creating virtual environment at ${venv_dir}"
        python3 -m venv "${venv_dir}" || fatal "Failed to create virtual environment"
    else
        log "Virtual environment already exists"
    fi
    
    # Activate virtual environment
    # shellcheck source=/dev/null
    source "${venv_dir}/bin/activate" || fatal "Failed to activate virtual environment"
    
    # Upgrade pip
    log "Upgrading pip..."
    pip install --upgrade pip setuptools wheel || fatal "Failed to upgrade pip"
    
    # Install Python dependencies
    if [[ -f "${PROJECT_ROOT}/requirements.txt" ]]; then
        log "Installing Python dependencies from requirements.txt"
        pip install -r "${PROJECT_ROOT}/requirements.txt" || fatal "Failed to install Python dependencies"
    else
        error "Warning: requirements.txt not found. Installing minimal dependencies."
        pip install numpy pandas matplotlib || fatal "Failed to install minimal dependencies"
    fi
    
    log "Python environment setup complete"
}

# ==============================================================================
# Repo Tool Setup
# ==============================================================================
setup_repo_tool() {
    log "Setting up repo tool..."
    
    # Check if repo is installed
    if ! command -v repo >/dev/null 2>&1; then
        log "Installing repo tool..."
        
        local repo_bin="${HOME}/.local/bin/repo"
        mkdir -p "$(dirname "${repo_bin}")"
        
        curl -o "${repo_bin}" https://storage.googleapis.com/git-repo-downloads/repo || \
            fatal "Failed to download repo tool"
        
        chmod +x "${repo_bin}"
        
        # Add to PATH if not already there
        if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
            export PATH="${HOME}/.local/bin:${PATH}"
            echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "${HOME}/.bashrc"
        fi
    fi
    
    # Verify repo version
    local repo_version
    repo_version=$(repo --version | head -n1 | awk '{print $2}')
    log "Repo tool version: ${repo_version}"
}

# ==============================================================================
# LTTng Verification
# ==============================================================================
verify_lttng() {
    log "Verifying LTTng installation..."
    
    # Check lttng command
    if ! command -v lttng >/dev/null 2>&1; then
        fatal "lttng command not found. Please install lttng-tools."
    fi
    
    # Check if user is in tracing group
    if ! groups | grep -q tracing; then
        error "Warning: Current user is not in 'tracing' group."
        error "Run: sudo usermod -aG tracing \$USER"
        error "Then log out and log back in."
        
        if [[ ${RUNNING_IN_CI} -eq 0 ]]; then
            fatal "Cannot continue without tracing group membership"
        fi
    fi
    
    # Verify UST libraries
    if ! pkg-config --exists lttng-ust; then
        fatal "lttng-ust development libraries not found"
    fi
    
    log "LTTng verification complete"
}

# ==============================================================================
# Directory Structure Setup
# ==============================================================================
setup_directories() {
    log "Setting up directory structure..."
    
    local dirs=(
        "${PROJECT_ROOT}/build"
        "${PROJECT_ROOT}/results"
        "${PROJECT_ROOT}/logs"
        "${PROJECT_ROOT}/cache"
        "${PROJECT_ROOT}/halo-os-src"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            mkdir -p "${dir}"
            log "Created directory: ${dir}"
        fi
    done
}

# ==============================================================================
# Environment Variables Export
# ==============================================================================
export_environment() {
    log "Exporting environment variables..."
    
    local env_file="${PROJECT_ROOT}/.env"
    
    cat > "${env_file}" << EOF
# Auto-generated environment configuration
# Generated at: $(date)

# Project paths
export PROJECT_ROOT="${PROJECT_ROOT}"
export BUILD_DIR="${PROJECT_ROOT}/build"
export RESULTS_DIR="${PROJECT_ROOT}/results"
export LOGS_DIR="${PROJECT_ROOT}/logs"
export CACHE_DIR="${PROJECT_ROOT}/cache"
export HALO_SRC_DIR="${PROJECT_ROOT}/halo-os-src"

# Python environment
export VIRTUAL_ENV="${PROJECT_ROOT}/venv"
export PATH="${PROJECT_ROOT}/venv/bin:\${PATH}"

# Build configuration
export CMAKE_BUILD_TYPE=RelWithDebInfo
export CMAKE_GENERATOR=Ninja

# Runtime configuration
export RUNNING_IN_CI=${RUNNING_IN_CI}
export RUNNING_IN_DOCKER=${RUNNING_IN_DOCKER}

# LTTng configuration
export LTTNG_HOME="${PROJECT_ROOT}/lttng"
EOF
    
    log "Environment variables exported to ${env_file}"
    log "Source this file in other scripts: source ${env_file}"
}

# ==============================================================================
# Validation
# ==============================================================================
validate_setup() {
    log "Validating setup..."
    
    local errors=0
    
    # Check critical commands
    local commands=(python3 pip cmake ninja git repo lttng)
    for cmd in "${commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            error "Command not found: ${cmd}"
            ((errors++))
        fi
    done
    
    # Check Python packages
    local packages=(numpy pandas)
    for pkg in "${packages[@]}"; do
        if ! python3 -c "import ${pkg}" 2>/dev/null; then
            error "Python package not found: ${pkg}"
            ((errors++))
        fi
    done
    
    # Check directories
    local dirs=("${PROJECT_ROOT}/build" "${PROJECT_ROOT}/results")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            error "Directory not found: ${dir}"
            ((errors++))
        fi
    done
    
    if [[ ${errors} -gt 0 ]]; then
        fatal "Validation failed with ${errors} error(s)"
    fi
    
    log "Validation complete - all checks passed"
}

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    log "========================================"
    log "Halo.OS Performance Harness Setup"
    log "========================================"
    
    detect_environment
    install_system_dependencies
    setup_python_environment
    setup_repo_tool
    verify_lttng
    setup_directories
    export_environment
    validate_setup
    
    log "========================================"
    log "Setup completed successfully!"
    log "========================================"
    log ""
    log "Next steps:"
    log "1. Source environment: source ${PROJECT_ROOT}/.env"
    log "2. Build Halo.OS: ./ci/build_halo.sh"
    log "3. Run experiment: ./ci/run_experiment.sh"
}

main "$@"
