#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Halo.OS performance harness environment ==="

# Use WORKSPACE env variable or default to current directory
WORKSPACE="${WORKSPACE:-$(pwd)}"

# Detect if running as root
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# -------------------------------
# Update package lists
# -------------------------------
$SUDO apt-get update

# -------------------------------
# Essential build tools
# -------------------------------
$SUDO apt-get install -y --no-install-recommends \
    build-essential cmake git wget curl unzip python3 python3-pip python3-venv

# -------------------------------
# LTTng tracing tools
# -------------------------------
$SUDO apt-get install -y liblttng-ust-dev lttng-tools babeltrace

# -------------------------------
# CAN utilities (optional)
# -------------------------------
$SUDO apt-get install -y can-utils iproute2

# -------------------------------
# Python packages
# -------------------------------
python3 -m pip install --upgrade pip
python3 -m pip install --no-cache-dir pandas numpy matplotlib

# -------------------------------
# Install 'repo' tool for manifest management
# -------------------------------
REPO_BIN="/usr/local/bin/repo"
if ! command -v repo &> /dev/null; then
    echo "Installing repo tool..."
    $SUDO curl -o "$REPO_BIN" https://storage.googleapis.com/git-repo-downloads/repo
    $SUDO chmod a+x "$REPO_BIN"
fi

# -------------------------------
# Create results directory in workspace
# -------------------------------
mkdir -p "$WORKSPACE/results"

# -------------------------------
# Optional: Docker environment tweaks
# -------------------------------
if [ -f /.dockerenv ]; then
    echo "Detected Docker environment"
    export LTTNG_HOME="$WORKSPACE/results/lttng"
fi

echo "=== Environment setup complete ==="

