#!/bin/bash
set -euo pipefail

echo "[$(date)] Setting up environment..."

# Update mirrors (use azure for consistency with logs)
sudo tee /etc/apt/sources.list.d/azure-mirror.list > /dev/null << EOF
deb http://azure.archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb http://azure.archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb http://azure.archive.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
EOF
sudo apt-get update -qq

# Core deps from your log + extras for VBSPro/LTTng
sudo apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build ca-certificates curl git \
    python3 python3-pip python3-venv \
    openjdk-11-jdk \
    lttng-tools liblttng-ust-dev liblttng-ust0

# Python venv (for analysis)
python3 -m venv venv
. venv/bin/activate
pip install --upgrade pip
pip install -r ../requirements.txt  # Assumes pinned deps

# Repo tool
if ! command -v repo >/dev/null; then
    curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
    chmod +x /tmp/repo
    sudo mv /tmp/repo /usr/local/bin/repo
fi

# JAVA_HOME for IDL/Gradle
export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
export PATH="$JAVA_HOME/bin:$PATH"

echo "[$(date)] Environment setup complete."
