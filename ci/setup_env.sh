#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Halo.OS performance harness environment ==="

# Detect if running as root
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# Update package lists
$SUDO apt-get update

# Essential build tools
$SUDO apt-get install -y --no-install-recommends \
    build-essential cmake git wget curl unzip python3 python3-pip python3-venv

# LTTng tracing
$SUDO apt-get install -y liblttng-ust-dev lttng-tools babeltrace

# CAN utilities (optional for VBS emulation)
$SUDO apt-get install -y can-utils iproute2

# Python packages
python3 -m pip install --upgrade pip
python3 -m pip install --no-cache-dir pandas numpy matplotlib

# Create results directory if missing
mkdir -p /workspace/results

# Optional: Docker environment tweaks
if [ -f /.dockerenv ]; then
    echo "Detected Docker environment"
    export LTTNG_HOME=/workspace/results/lttng
fi

echo "=== Environment setup complete ==="
