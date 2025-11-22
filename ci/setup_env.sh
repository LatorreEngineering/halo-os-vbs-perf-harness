#!/bin/bash
set -euo pipefail

echo "[$(date)] Setting up environment..."

# Add official LTTng PPA
sudo add-apt-repository ppa:lttng/ppa -y
sudo apt-get update -qq

# Install everything we need (no DKMS removed long ago)
sudo apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build ca-certificates curl git \
    python3 python3-pip python3-venv \
    openjdk-11-jdk \
    lttng-tools liblttng-ust1 liblttng-ust-dev \
    babeltrace

# Create venv and activate it — THIS LINE FIXES SHELLCHECK FOREVER
python3 -m venv venv
# shellcheck source=/dev/null
source venv/bin/activate

pip install --upgrade pip
if [ -f requirements.txt ]; then
    pip install -r requirements.txt
fi

# Repo tool
if ! command -v repo >/dev/null 2>&1; then
    curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
    chmod +x /tmp/repo
    sudo mv /tmp/repo /usr/local/bin/repo
fi

# Java
export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
export PATH="$JAVA_HOME/bin:$PATH"

echo "[$(date)] Environment setup complete."
