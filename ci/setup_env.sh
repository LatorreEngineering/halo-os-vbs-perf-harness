#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Halo.OS performance harness environment ==="

# ------------------------------------------------------------
# Workspace and results directory
# ------------------------------------------------------------
WORKSPACE="${WORKSPACE:-$(pwd)}"
RESULTS_DIR="${WORKSPACE}/results"
mkdir -p "$RESULTS_DIR"
echo "[INFO] Results directory: $RESULTS_DIR"

# ------------------------------------------------------------
# Detect privileged mode
# ------------------------------------------------------------
SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
fi

# ------------------------------------------------------------
# Detect environment: Local vs CI
# ------------------------------------------------------------
if [ -z "${GITHUB_ACTIONS:-}" ]; then
    echo "[LOCAL DEV] Installing system dependencies..."
    $SUDO apt-get update -qq

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

    for pkg in "${PKGS[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            echo "[LOCAL DEV] Installing missing package: $pkg"
            $SUDO apt-get install -y --no-install-recommends "$pkg"
        fi
    done
else
    echo "[CI] Running inside GitHub Actions — skipping system installs"
fi

# ------------------------------------------------------------
# Repo tool installation (local only)
# ------------------------------------------------------------
if [ -z "${GITHUB_ACTIONS:-}" ]; then
    echo "[LOCAL DEV] Ensuring 'repo' tool is installed..."
    REPO_BIN="$HOME/bin/repo"
    mkdir -p "$HOME/bin"

    if ! command -v repo >/dev/null 2>&1; then
        echo "[LOCAL DEV] Installing 'repo' tool..."
        curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO_BIN"
        chmod a+x "$REPO_BIN"
    fi

    export PATH="$HOME/bin:$PATH"
    echo "[LOCAL DEV] 'repo' tool available at $(command -v repo)"
else
    echo "[CI] Repo tool installation is handled by CI — skipping"
fi

# ------------------------------------------------------------
# Docker detection: adjust LTTNG_HOME
# ------------------------------------------------------------
if [ -f /.dockerenv ]; then
    echo "[DOCKER] Setting LTTNG_HOME to $RESULTS_DIR/lttng"
    export LTTNG_HOME="$RESULTS_DIR/lttng"
fi

echo "=== Environment setup complete ==="
