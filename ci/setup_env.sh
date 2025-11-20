#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Halo.OS performance harness environment ==="

# Workspace directory
WORKSPACE="${WORKSPACE:-$(pwd)}"

# Detect privileged mode
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# ------------------------------------------------------------
# Minimal installation for local developers only
# ------------------------------------------------------------
if [ -z "${GITHUB_ACTIONS:-}" ]; then
    echo "Running outside GitHub Actions — installing system packages"

    $SUDO apt-get update

    $SUDO apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        curl \
        wget \
        unzip \
        python3 \
        python3-pip \
        python3-venv \
        liblttng-ust-dev \
        lttng-tools \
        babeltrace \
        can-utils \
        iproute2
else
    echo "Running inside GitHub Actions — skipping apt-get installs"
fi

# ------------------------------------------------------------
# Python deps are installed by CI.yml — not here
# ------------------------------------------------------------

# ------------------------------------------------------------
# Repo tool is installed only by CI.yml
# ------------------------------------------------------------
if [ ! -z "${GITHUB_ACTIONS:-}" ]; then
    echo "Skipping repo installation inside setup_env.sh (handled by CI)"
else
    # Local developer installs repo here
    REPO_BIN="$HOME/bin/repo"
    mkdir -p "$HOME/bin"

    if ! command -v repo >/dev/null 2>&1; then
        echo "Installing repo tool for local environment"
        curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO_BIN"
        chmod a+x "$REPO_BIN"
    fi

    export PATH="$HOME/bin:$PATH"
fi

# ------------------------------------------------------------
# Prepare results output directory
# ------------------------------------------------------------
mkdir -p "$WORKSPACE/results"

# ------------------------------------------------------------
# Docker environment detection
# ------------------------------------------------------------
if [ -f /.dockerenv ]; then
    echo "Running inside Docker — adjusting LTTNG_HOME"
    export LTTNG_HOME="$WORKSPACE/results/lttng"
fi

echo "=== Environment setup complete ==="
