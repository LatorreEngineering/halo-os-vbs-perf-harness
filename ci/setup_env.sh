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
# CAN utilities (optional for VBS emulation)
# -------------------------------
$SUDO apt-get install -y can-utils iproute2

# -------------------------------
# Python packages
# -------------------------------
python3 -m pip install --upgrade pip
python3 -m pip install --no-cache-dir pandas numpy matplotlib flake8 black

# -------------------------------
# Install 'repo' tool for manifest management
# -------------------------------
REPO_BIN="$HOME/bin/repo"
mkdir -p "$HOME/bin"
if ! command -v repo &> /dev/null; then
    echo "Installing repo tool..."
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO_BIN"
    chmod a+x "$REPO_BIN"
fi
export PATH="$HOME/bin:$PATH"

# -------------------------------
# Create results directory in workspace
# -------------------------------
mkdir -p "$WORKSPACE/results"

# -------------------------------
# Docker environment tweaks
# -------------------------------
if [ -f /.dockerenv ]; then
    echo "Detected Docker environment"
    export LTTNG_HOME="$WORKSPACE/results/lttng"
fi

echo "=== Environment setup complete ==="


