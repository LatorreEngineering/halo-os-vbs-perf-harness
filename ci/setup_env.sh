#!/bin/bash
# ci/setup_env.sh
# Purpose: Install and validate all dependencies for Halo.OS performance testing
# Usage: ./ci/setup_env.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_FILE="${PROJECT_ROOT}/setup.log"
readonly PYTHON_MIN_VERSION="3.10"
readonly REPO_TOOL_VERSION="2.41"

log() { echo "[$(date +'%F %T')] $*" | tee -a "${LOG_FILE}"; }
error() { echo "[$(date +'%F %T')] ERROR: $*" | tee -a "${LOG_FILE}" >&2; }
fatal() { error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Detect environment
# ---------------------------------------------------------------------------
detect_environment() {
    log "Detecting environment..."
    [[ -f /etc/os-release ]] || fatal "/etc/os-release not found"
    . /etc/os-release
    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"
    log "Detected OS: $OS_ID $OS_VERSION"

    [[ $OS_ID != "ubuntu" || $OS_VERSION != "22.04" ]] && log "⚠ Recommended: Ubuntu 22.04 LTS"

    export RUNNING_IN_CI=${CI:-0}
    [[ -n "${GITHUB_ACTIONS:-}" ]] && RUNNING_IN_CI=1

    export RUNNING_IN_DOCKER=0
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        RUNNING_IN_DOCKER=1
    fi

    log "CI environment: $RUNNING_IN_CI, Docker: $RUNNING_IN_DOCKER"
}

# ---------------------------------------------------------------------------
# Install system dependencies
# ---------------------------------------------------------------------------
install_system_dependencies() {
    log "Installing system packages..."
    SUDO=""
    [[ $EUID -ne 0 && $(command -v sudo) ]] && SUDO="sudo"

    ${SUDO} apt-get update -qq || fatal "Failed to update apt"
    
    local packages=(
        build-essential cmake ninja-build git curl wget python3 python3-pip python3-venv
        lttng-tools lttng-modules-dkms liblttng-ust-dev liblttng-ctl-dev liburcu-dev pkg-config
    )

    log "Installing: ${packages[*]}"
    ${SUDO} apt-get install -y "${packages[@]}" || fatal "Failed installing system packages"
}

# ---------------------------------------------------------------------------
# Python environment
# ---------------------------------------------------------------------------
setup_python_environment() {
    log "Setting up Python environment..."
    command -v python3 >/dev/null || fatal "Python3 not found"
    python3 -c "import sys; exit(0 if sys.version_info >= (3,10) else 1)" || \
        fatal "Python >= 3.10 required"

    local venv_dir="${PROJECT_ROOT}/venv"
    [[ ! -d "$venv_dir" ]] && python3 -m venv "$venv_dir" && log "Virtualenv created"
    # shellcheck source=/dev/null
    source "$venv_dir/bin/activate"

    pip install --upgrade pip setuptools wheel
    if [[ -f "${PROJECT_ROOT}/requirements.txt" ]]; then
        pip install -r "${PROJECT_ROOT}/requirements.txt"
    else
        log "requirements.txt missing, installing minimal dependencies"
        pip install numpy pandas matplotlib
    fi
}

# ---------------------------------------------------------------------------
# Repo tool setup
# ---------------------------------------------------------------------------
setup_repo_tool() {
    log "Setting up repo tool..."
    if ! command -v repo >/dev/null; then
        mkdir -p "${HOME}/.local/bin"
        curl -sSfL https://storage.googleapis.com/git-repo-downloads/repo -o "${HOME}/.local/bin/repo"
        chmod +x "${HOME}/.local/bin/repo"
        export PATH="${HOME}/.local/bin:${PATH}"
        grep -q "${HOME}/.local/bin" <<< "$PATH" || echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
    fi
    log "Repo tool version: $(repo --version | head -n1)"
}

# ---------------------------------------------------------------------------
# LTTng verification
# ---------------------------------------------------------------------------
verify_lttng() {
    log "Verifying LTTng..."
    command -v lttng >/dev/null || fatal "lttng command missing"

    if [[ $RUNNING_IN_CI -eq 0 ]] && ! groups | grep -q tracing; then
        log "⚠ User not in 'tracing' group. Required for full tracing functionality"
    fi

    pkg-config --exists lttng-ust || fatal "lttng-ust dev libraries not found"
    log "LTTng OK"
}

# ---------------------------------------------------------------------------
# Setup directories
# ---------------------------------------------------------------------------
setup_directories() {
    log "Setting up directories..."
    for dir in build results logs cache halo-os-src; do
        mkdir -p "${PROJECT_ROOT}/${dir}"
    done
}

# ---------------------------------------------------------------------------
# Export environment variables
# ---------------------------------------------------------------------------
export_environment() {
    log "Exporting environment variables..."
    cat > "${PROJECT_ROOT}/.env" << EOF
export PROJECT_ROOT="${PROJECT_ROOT}"
export BUILD_DIR="${PROJECT_ROOT}/build"
export RESULTS_DIR="${PROJECT_ROOT}/results"
export LOGS_DIR="${PROJECT_ROOT}/logs"
export CACHE_DIR="${PROJECT_ROOT}/cache"
export HALO_SRC_DIR="${PROJECT_ROOT}/halo-os-src"
export VIRTUAL_ENV="${PROJECT_ROOT}/venv"
export PATH="${PROJECT_ROOT}/venv/bin:\$PATH"
export CMAKE_BUILD_TYPE=RelWithDebInfo
export CMAKE_GENERATOR=Ninja
export RUNNING_IN_CI=${RUNNING_IN_CI}
export RUNNING_IN_DOCKER=${RUNNING_IN_DOCKER}
EOF
    log "Environment exported to ${PROJECT_ROOT}/.env"
}

# ---------------------------------------------------------------------------
# Validate setup
# ---------------------------------------------------------------------------
validate_setup() {
    log "Validating setup..."
    local errors=0

    for cmd in python3 pip cmake ninja git repo lttng; do
        command -v "$cmd" >/dev/null || { error "$cmd missing"; ((errors++)); }
    done

    for pkg in numpy pandas; do
        python3 -c "import $pkg" 2>/dev/null || { error "Python package $pkg missing"; ((errors++)); }
    done

    for dir in build results; do
        [[ -d "${PROJECT_ROOT}/${dir}" ]] || { error "Directory ${dir} missing"; ((errors++)); }
    done

    [[ $errors -gt 0 ]] && fatal "Setup validation failed with $errors error(s)"
    log "Setup validation passed"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log "===================================="
    log "Halo.OS Performance Setup"
    log "===================================="

    detect_environment
    install_system_dependencies
    setup_python_environment
    setup_repo_tool
    verify_lttng
    setup_directories
    export_environment
    validate_setup

    log "Setup completed successfully!"
    log "Next steps:"
    log "1. Source environment: source ${PROJECT_ROOT}/.env"
    log "2. Build Halo.OS: ./ci/build_halo.sh"
    log "3. Run experiment: ./ci/run_experiment.sh"
}

main "$@"
