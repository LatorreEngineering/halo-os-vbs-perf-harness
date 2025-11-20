#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing host dependencies for Halo.OS perf harness ==="

# Update package lists
sudo apt update

# Essential build tools
sudo apt install -y build-essential cmake git wget curl unzip python3 python3-pip python3-venv

# LTTng-UST for tracing
sudo apt install -y liblttng-ust-dev lttng-tools babeltrace

# CAN utilities (optional for VBS emulation)
sudo apt install -y can-utils

# Python dependencies
pip3 install --upgrade pip
pip3 install pandas numpy matplotlib

echo "=== Environment setup complete ==="
