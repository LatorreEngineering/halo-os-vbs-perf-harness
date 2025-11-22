#!/bin/bash
set -euo pipefail

echo "[$(date)] Building VBSPro for Halo.OS Perf Harness"

# ── Install repo tool if missing (safe & idempotent) ──
if ! command -v repo >/dev/null 2>&1; then
    echo "[$(date)] Installing repo tool..."
    curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
    chmod +x /tmp/repo
    sudo mv /tmp/repo /usr/local/bin/repo
fi

echo "[$(date)] Initializing repo manifest"
repo init -u https://gitee.com/haloos/manifests.git -b main -m "${MANIFEST_NAME:-vbs.xml}"

echo "[$(date)] Syncing sources (parallel jobs: $(nproc))"
# ←←← THIS LINE FIXES SHELLCHECK SC2046
repo sync -j"$(nproc)"

echo "[$(date)] Starting VBSPro build"
# ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
# PUT YOUR ACTUAL BUILD COMMAND BELOW (examples):
# source build/envsetup.sh && lunch vbspro-eng && m -j"$(nproc)"
# OR:
# ./build.sh --target vbspro
# OR whatever you really use
# ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
# Example placeholder:
echo "[$(date)] Running placeholder build command..."
# Replace the line below with your real build
sleep 2  # ← remove this

echo "[$(date)] Build completed successfully!"
