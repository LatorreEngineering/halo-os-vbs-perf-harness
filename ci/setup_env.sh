#!/bin/bash
set -euo pipefail

echo "[$(date)] Setting up environment..."

# Add official LTTng PPA for Ubuntu 22.04 (stable branch)
sudo add-apt-repository ppa:lttng/ppa -y
sudo apt-get update -qq

# Install deps: Core build tools + correct LTTng packages (liblttng-ust0 -> liblttng-ust1 from PPA)
sudo apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build ca-certificates curl git \
    python3 python3-pip python3-venv \
    openjdk-11-jdk \
    lttng-tools liblttng-ust1 liblttng-ust-dev lttng-modules-dkms \
    babeltrace

# Python venv for analysis
python3 -m venv venv
# shellcheck disable=SC1091  # Dynamic source after venv creation
. venv/bin/activate
pip install --upgrade pip
[ -f requirements.txt ] && pip install -r requirements.txt || echo "No requirements.txt found"

# Repo tool (for Gitee manifests)
if ! command -v repo >/dev/null; then
    curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
    chmod +x /tmp/repo
    sudo mv /tmp/repo /usr/local/bin/repo
fi

# JAVA_HOME for Gradle/IDL tools
export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
export PATH="$JAVA_HOME/bin:$PATH"

echo "[$(date)] Environment setup complete."
