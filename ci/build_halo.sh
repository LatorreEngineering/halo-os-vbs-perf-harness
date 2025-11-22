#!/bin/bash
set -euo pipefail

echo "[$(date)] Building VBSPro for Halo.OS Perf Harness"

# ── Ensure repo tool is available (critical) ──
if ! command -v repo >/dev/null 2>&1; then
    echo "[$(date)] Installing repo tool..."
    curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
    chmod +x /tmp/repo
    sudo mv /tmp/repo /usr/local/bin/repo
fi

echo "[$(date)] Init repo"
repo init -u https://gitee.com/haloos/manifests.git -b main -m "${MANIFEST_NAME:-vbs.xml}"

echo "[$(date)] Sync repo"
repo sync -j$(nproc)

echo "[$(date)] Starting build"
# Replace with your actual build command (example below)
# source build/envsetup.sh && lunch vbspro-eng && m -j$(nproc)
# Or whatever your real build steps are — put them here:
./repo.sh build  # ← change this to your real build command

echo "[$(date)] Build completed successfully!"
