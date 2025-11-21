#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Halo.OS performance harness environment ==="

# Workspace directory
WORKSPACE="${WORKSPACE:-$(pwd)}"
RESULTS_DIR="${WORKSPACE}/results"

# Detect privileged mode
SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
fi

# ------------------------------------------------------------
# Detect environment
# ------------------------------------------------------------
if [ -z "${GITHUB_ACTIONS:-}" ]; then
    echo "[LOCAL DEV] Installing system dependencies..."
    $SUDO apt-get update

    # Minimal required packages
    PKGS=(
        build-essential
        cmake
        git
        curl
        wget
        unzip
        python3
        python3-pip
        python3-venv
        liblttng-ust-dev
        lttng-tools
        babeltrace
        can-utils
        iproute2
    )

    # Install missing packages only
    for pkg in "${PKGS[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            $SUDO apt-get install -y --no-install-recommends "$pkg"
        fi
    done
else
    echo "[CI] Running inside GitHub Actions — skipping apt-get installs"
fi

# ------------------------------------------------------------
# Repo tool installation (local only)
# ------------------------------------------------------------
if [ -z "${GITHUB_ACTIONS:-}" ]; then
    echo "[LOCAL DEV] Ensuring 'repo' tool is installed..."
    REPO_BIN="$HOME/bin/repo"
    mkdir -p "$HOME/bin"

    if ! command -v repo >/dev/null 2>&1; then
        echo "Installing repo tool..."
        curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO_BIN"
        chmod a+x "$REPO_BIN"
    fi

    export PATH="$HOME/bin:$PATH"
    echo "[LOCAL DEV] 'repo' tool is available at $(command -v repo)"
else
    echo "[CI] Repo tool is installed by CI — skipping"
fi

# ------------------------------------------------------------
# Prepare results output directory
# ------------------------------------------------------------
mkdir -p "$RESULTS_DIR"
echo "[INFO] Results directory: $RESULTS_DIR"

# ------------------------------------------------------------
# Docker environment detection
# ------------------------------------------------------------
if [ -f /.dockerenv ]; then
    echo "[DOCKER] Setting LTTNG_HOME"
    export LTTNG_HOME="$RESULTS_DIR/lttng"
fi

echo "=== Environment setup complete ==="
