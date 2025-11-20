#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# ------------------------------------------------------------
# Workspace Setup
# ------------------------------------------------------------
WORKSPACE="${WORKSPACE:-$(pwd)}"
MANIFEST_DIR="$WORKSPACE/manifests"
REPO_DIR="$WORKSPACE/repo"
mkdir -p "$MANIFEST_DIR" "$REPO_DIR"

# ------------------------------------------------------------
# Manifest Selection
# ------------------------------------------------------------
PRIMARY_MANIFEST="manifest_20250825.xml"
FALLBACK_MANIFEST="default.xml"

PRIMARY_URL="https://gitee.com/haloos/manifests/raw/main/${PRIMARY_MANIFEST}"
FALLBACK_URL="https://gitee.com/haloos/manifests/raw/main/${FALLBACK_MANIFEST}"

PRIMARY_PATH="$MANIFEST_DIR/$PRIMARY_MANIFEST"
FALLBACK_PATH="$MANIFEST_DIR/$FALLBACK_MANIFEST"

download_manifest() {
    local url="$1"
    local dest="$2"

    if [ -n "${GITEE_TOKEN:-}" ]; then
        curl -fsSL -H "Authorization: token ${GITEE_TOKEN}" -o "$dest" "$url"
    else
        curl -fsSL -o "$dest" "$url"
    fi
}

echo "Downloading primary manifest: $PRIMARY_MANIFEST"
if ! download_manifest "$PRIMARY_URL" "$PRIMARY_PATH"; then
    echo "⚠️ Primary manifest not found, trying fallback..."
    if ! download_manifest "$FALLBACK_URL" "$FALLBACK_PATH"; then
        echo "❌ Error: Failed to download fallback manifest ($FALLBACK_MANIFEST)"
        exit 1
    fi
    MANIFEST_FILE="$FALLBACK_PATH"
else
    MANIFEST_FILE="$PRIMARY_PATH"
fi

echo "Using manifest: $MANIFEST_FILE"

# ------------------------------------------------------------
# Repo initialization (LOCAL ONLY)
# CI already performs repo init + sync
# ------------------------------------------------------------
if [ -z "${GITHUB_ACTIONS:-}" ]; then
    echo "Running locally — performing repo init + repo sync"

    cd "$REPO_DIR"

    # Validate repo installed
    if ! command -v repo >/dev/null 2>&1; then
        echo "❌ repo tool not installed — run setup_env.sh"
        exit 1
    fi

    REPO_URL="https://gitee.com/haloos/manifest.git"
    if [ -n "${GITEE_TOKEN:-}" ]; then
        # Correct authenticated domain
        REPO_URL="https://${GITEE_TOKEN}@gitee.com/haloos/manifest.git"
    fi

    echo "Initializing repo..."
    repo init -u "$REPO_URL" -m "$MANIFEST_FILE"

    echo "Syncing repo..."
    repo sync -j"$(nproc)" --force-sync
else
    echo "Running inside GitHub Actions — skipping repo sync (already done in CI)"
fi

# ------------------------------------------------------------
# Build Halo.OS Real-Time Demo
# ------------------------------------------------------------
DEMO_DIR="$REPO_DIR/apps/rt_demo"
BUILD_DIR="$DEMO_DIR/build"

if [ ! -d "$DEMO_DIR" ]; then
    echo "❌ Error: Demo directory not found in repo checkout"
    exit 1
fi

echo "Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ------------------------------------------------------------
# Toolchain selection
# Prefer toolchain from repo if available
# ------------------------------------------------------------
if [ -f "$REPO_DIR/toolchains/jetson.cmake" ]; then
    TOOLCHAIN_FILE="$REPO_DIR/toolchains/jetson.cmake"
    echo "Using repo Jetson toolchain"
elif [ -f "$REPO_DIR/toolchains/host.cmake" ]; then
    TOOLCHAIN_FILE="$REPO_DIR/toolchains/host.cmake"
    echo "Using repo host/x86 toolchain"
elif [ -f "$WORKSPACE/toolchains/host.cmake" ]; then
    TOOLCHAIN_FILE="$WORKSPACE/toolchains/host.cmake"
    echo "Using workspace host toolchain"
else
    echo "❌ Error: No valid toolchain found"
    exit 1
fi

# ------------------------------------------------------------
# Build with CMake
# ------------------------------------------------------------
echo "Configuring CMake..."
cmake "$DEMO_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"

echo "Building..."
make -j"$(nproc)"

echo "=== Build complete ==="
echo "Executable: $BUILD_DIR/rt_demo"
