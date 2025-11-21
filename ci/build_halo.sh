#!/usr/bin/env bash
set -euo pipefail

echo "=== Building Halo.OS instrumented demo ==="

# ------------------------------------------------------------
# Workspace and directories
# ------------------------------------------------------------
WORKSPACE="${WORKSPACE:-$(pwd)}"
MANIFEST_DIR="$WORKSPACE/manifests"
REPO_DIR="$WORKSPACE/repo"
mkdir -p "$MANIFEST_DIR" "$REPO_DIR"

# ------------------------------------------------------------
# Manifest selection
# ------------------------------------------------------------
MANIFEST_NAME="${PRIMARY_MANIFEST:-pinned_manifest.xml}"
MANIFEST_URL="https://gitee.com/haloos/manifests/raw/main/$MANIFEST_NAME"
MANIFEST_PATH="$MANIFEST_DIR/$MANIFEST_NAME"

download_manifest() {
    local url="$1"
    local dest="$2"
    echo "[INFO] Downloading manifest from $url"
    if [ -n "${GITEE_TOKEN:-}" ]; then
        curl -fsSL -H "Authorization: token $GITEE_TOKEN" -o "$dest" "$url"
    else
        curl -fsSL -o "$dest" "$url"
    fi
}

# Download pinned manifest
if ! download_manifest "$MANIFEST_URL" "$MANIFEST_PATH"; then
    echo "❌ Error: Failed to download manifest $MANIFEST_NAME"
    exit 1
fi
echo "[INFO] Using manifest: $MANIFEST_PATH"

# ------------------------------------------------------------
# Repo initialization (local only)
# ------------------------------------------------------------
if [ -z "${GITHUB_ACTIONS:-}" ]; then
    echo "[LOCAL] Performing repo init + sync"

    cd "$REPO_DIR"

    if ! command -v repo >/dev/null 2>&1; then
        echo "❌ Error: 'repo' tool not installed — run setup_env.sh"
        exit 1
    fi

    REPO_URL="https://gitee.com/haloos/manifest.git"
    if [ -n "${GITEE_TOKEN:-}" ]; then
        REPO_URL="https://${GITEE_TOKEN}@gitee.com/haloos/manifest.git"
    fi

    echo "Initializing repo..."
    repo init -u "$REPO_URL" -m "$MANIFEST_PATH" --quiet
    echo "Syncing repo..."
    repo sync -j"$(nproc)" --force-sync --quiet
else
    echo "[CI] Repo already initialized and synced by workflow"
fi

# ------------------------------------------------------------
# Build Halo.OS demo
# ------------------------------------------------------------
DEMO_DIR="$REPO_DIR/apps/rt_demo"
BUILD_DIR="$DEMO_DIR/build"

if [ ! -d "$DEMO_DIR" ]; then
    echo "❌ Error: Demo directory $DEMO_DIR does not exist"
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ------------------------------------------------------------
# Toolchain selection
# ------------------------------------------------------------
TOOLCHAIN_FILE=""
if [ -f "$REPO_DIR/toolchains/jetson.cmake" ]; then
    TOOLCHAIN_FILE="$REPO_DIR/toolchains/jetson.cmake"
    echo "[INFO] Using repo Jetson toolchain"
elif [ -f "$REPO_DIR/toolchains/host.cmake" ]; then
    TOOLCHAIN_FILE="$REPO_DIR/toolchains/host.cmake"
    echo "[INFO] Using repo host/x86 toolchain"
elif [ -f "$WORKSPACE/toolchains/host.cmake" ]; then
    TOOLCHAIN_FILE="$WORKSPACE/toolchains/host.cmake"
    echo "[INFO] Using workspace host toolchain"
else
    echo "❌ Error: No toolchain found in repo or workspace"
    exit 1
fi

# ------------------------------------------------------------
# Build with CMake
# ------------------------------------------------------------
echo "[INFO] Configuring CMake..."
cmake "$DEMO_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"

echo "[INFO] Building..."
make -j"$(nproc)"

echo "=== Build complete ==="
echo "Executable located at $BUILD_DIR/rt_demo"
