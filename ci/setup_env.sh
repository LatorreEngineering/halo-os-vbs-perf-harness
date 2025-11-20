#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Halo.OS performance harness environment ==="

# Detect if running as root
if [ "${EUID}" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# -------------------------------
# Update system package lists
# -------------------------------
echo "=== Updating APT package lists ==="
$SUDO apt-get update -y

# -------------------------------
# Install essential tools
# -------------------------------
echo "=== Installing required system packages ==="
$SUDO apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    unzip \
    python3 \
    python3-pip \
    python3-venv \
    ca-certificates

# -------------------------------
# Install LTTng dependencies
# -------------------------------
echo "=== Installing LTTng tracing tools ==="
$SUDO apt-get install -y \
    liblttng-ust-dev \
    lttng-tools \
    babeltrace

# -------------------------------
# Install CAN utilities
# -------------------------------
echo "=== Installing CAN bus utilities ==="
$SUDO apt-get install -y \
    can-utils \
    iproute2

# -------------------------------
# Install Python dependencies
# -------------------------------
echo "=== Installing Python packages ==="
python3 -m pip install --upgrade pip
python3 -m pip install --no-cache-dir \
    pandas \
    numpy \
    matplotlib

# -------------------------------
# Install Android repo tool
# -------------------------------
echo "=== Installing Android repo tool ==="

# Primary Google source
GOOGLE_REPO_URL="https://storage.googleapis.com/git-repo-downloads/repo"

# Gitee mirror fallback
GITEE_REPO_URL="https://gitee.com/mirrors/repo/raw/master/repo"

install_repo_tool() {
    local url="${1}"
    echo "Attempting to download repo tool from: ${url}"
    if curl -L "${url}" -o /usr/local/bin/repo; then
        chmod +x /usr/local/bin/repo
        echo "Repo tool installed successfully from: ${url}"
        return 0
    else
        echo "Failed to download from: ${url}"
        return 1
    fi
}

# Try Google first, then Gitee
if ! install_repo_tool "${GOOGLE_REPO_URL}"; then
    echo "Retrying with Gitee mirror..."
    install_repo_tool "${GITEE_REPO_URL}" || {
        echo "❌ ERROR: Failed to install repo tool from both Google and Gitee."
        exit 1
    }
fi

# -------------------------------
# Workspace directories
# -------------------------------
echo "=== Ensuring workspace directories exist ==="

# WORKSPACE is provided by GitHub Actions
if [ -z "${WORKSPACE:-}" ]; then
    export WORKSPACE="${PWD}"
fi

mkdir -p "${WORKSPACE}/results"
mkdir -p "${WORKSPACE}/repo"

# -------------------------------
# Docker environment tweaks
# -------------------------------
if [ -f /.dockerenv ]; then
    echo "Detected Docker environment – applying LTTng HOME override"
    export LTTNG_HOME="${WORKSPACE}/results/lttng"
fi

echo "=== Environment setup complete ==="
