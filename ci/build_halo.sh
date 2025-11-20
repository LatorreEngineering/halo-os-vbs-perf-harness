#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# ----------------------------------------
# Workspace configuration
# ----------------------------------------
WORKSPACE="${WORKSPACE:-$(pwd)}"
MANIFEST_DIR="$WORKSPACE/manifests"
MANIFEST_FILE="$MANIFEST_DIR/pinned_manifest.xml"
REPO_DIR="$WORKSPACE/repo"

mkdir -p "$MANIFEST_DIR"
mkdir -p "$REPO_DIR"

# ----------------------------------------
# Download manifest (with fallback)
# ----------------------------------------
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Downloading pinned_manifest.xml..."

    PRIMARY_URL="https://gitee.com/haloos/manifest/raw/main/pinned_manifest.xml"
    MIRROR_URL="https://gitee.com/mirrors/haloos-manifest/raw/main/pinned_manifest.xml"

    if curl -fSL "$PRIMARY_URL" -o "$MANIFEST_FILE"; then
        echo "Downloaded manifest from primary source."
    else
        echo "Primary source failed, trying mirror..."
        if curl -fSL "$MIRROR_URL" -o "$MANIFEST_FILE"; then
            echo "Downloaded manifest from mirror."
        else
            echo "❌ ERROR: Failed to download manifest from both sources."
            exit 1
        fi
    fi
fi

# ----------------------------------------
# Initialize repo
# ----------------------------------------
cd "$REPO_DIR"

# Remove stale .repo if present (common in CI)
if [ -d ".repo" ]; then
    echo "Cleaning up stale repo directory..."
    rm -rf .repo
fi

echo "Initializing repo..."

repo init \
    -u https://gitee.com/haloos/manifest.git \
    --repo-dir="$REPO_DIR" \
    --manifest-name="$(basename "$MANIFEST_FILE")" \
    --quiet

# Copy our external pinned manifest into .repo/manifests
cp "$MANIFEST_FILE" "$REPO_DIR/.repo/manifests/"

echo "Running repo sync (this may take a while)..."

repo sync \
    --force-sync \
    --no-clone-bundle \
    --no-tags \
    --optimized-fetch \
    --repo-dir="$REPO_DIR" \
    --quiet

echo "Repo sync complete."

# ----------------------------------------
# Locate and build Halo rt_demo
# ----------------------------------------
DEMO_DIR="$REPO_DIR/apps/rt_demo"
BUILD_DIR="$DEMO_DIR/build"

if [ ! -d "$DEMO_DIR" ]; then
    echo "❌ ERROR: rt_demo directory not found at: $DEMO_DIR"
    echo "Repo sync may have failed or manifest may be incorrect."
    exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ----------------------------------------
# Toolchain detection
# ----------------------------------------
TOOLCHAIN_DIR="$WORKSPACE/toolchains"
JETSON_TC="$TOOLCHAIN_DIR/jetson.cmake"
HOST_TC="$TOOLCHAIN_DIR/host.cmake"

if [ -f "$JETSON_TC" ]; then
    TOOLCHAIN="$JETSON_TC"
    echo "Using Jetson toolchain."
elif [ -f "$HOST_TC" ]; then
    TOOLCHAIN="$HOST_TC"
    echo "Using host/x86 toolchain."
else
    echo "❌ ERROR: No toolchain found in $TOOLCHAIN_DIR"
    exit 1
fi

# ----------------------------------------
# Build (debug logs enabled)
# ----------------------------------------
echo "Running CMake..."
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"

echo "Building..."
make -j"$(nproc)"

echo "=== Build complete ==="
echo "Executable located at:"
echo "   $BUILD_DIR/rt_demo"
