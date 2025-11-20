#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# ----------------------------------------
# Workspace configuration
# ----------------------------------------
WORKSPACE="${WORKSPACE:-$(pwd)}"
MANIFEST_DIR="$WORKSPACE/manifests"
MANIFEST_FILE="$MANIFEST_DIR/default.xml"
REPO_DIR="$WORKSPACE/repo"

mkdir -p "$MANIFEST_DIR"
mkdir -p "$REPO_DIR"

# ----------------------------------------
# Download official Halo.OS manifest
# ----------------------------------------
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Downloading Halo.OS default manifest..."

    MANIFEST_URL="https://gitee.com/haloos/manifest/raw/main/default.xml"

    if ! curl -fSL "$MANIFEST_URL" -o "$MANIFEST_FILE"; then
        echo "❌ ERROR: Could not download default.xml from Halo.OS manifest repo."
        exit 1
    fi

    echo "Downloaded manifest → $MANIFEST_FILE"
fi

# ----------------------------------------
# Repo initialization
# ----------------------------------------
cd "$REPO_DIR"

# Clear stale repo metadata
if [ -d ".repo" ]; then
    echo "Cleaning up old .repo directory..."
    rm -rf .repo
fi

echo "Initializing repo..."

repo init \
    -u https://gitee.com/haloos/manifest.git \
    --repo-dir="$REPO_DIR" \
    --manifest-name="default.xml" \
    --quiet

# Copy downloaded manifest into repo manifest store
cp "$MANIFEST_FILE" "$REPO_DIR/.repo/manifests/"

echo "Running repo sync..."

repo sync \
    --force-sync \
    --no-clone-bundle \
    --no-tags \
    --optimized-fetch \
    --repo-dir="$REPO_DIR" \
    --quiet

echo "Repo sync complete."

# ----------------------------------------
# Build Halo OS rt_demo
# ----------------------------------------
DEMO_DIR="$REPO_DIR/apps/rt_demo"
BUILD_DIR="$DEMO_DIR/build"

if [ ! -d "$DEMO_DIR" ]; then
    echo "❌ ERROR: rt_demo directory not found at: $DEMO_DIR"
    echo "Check the manifest and repo sync results."
    exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ----------------------------------------
# Toolchain detection
# ----------------------------------------
TOOLCHAIN_DIR="$WORKSPACE/toolchains"

if [ -f "$TOOLCHAIN_DIR/jetson.cmake" ]; then
    TOOLCHAIN="$TOOLCHAIN_DIR/jetson.cmake"
    echo "Using Jetson toolchain"
elif [ -f "$TOOLCHAIN_DIR/host.cmake" ]; then
    TOOLCHAIN="$TOOLCHAIN_DIR/host.cmake"
    echo "Using host toolchain"
else
    echo "❌ ERROR: No toolchain found in $TOOLCHAIN_DIR"
    exit 1
fi

# ----------------------------------------
# Build
# ----------------------------------------
echo "Configuring CMake..."
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"

echo "Building..."
make -j"$(nproc)"

echo "=== Build complete ==="
echo "Executable: $BUILD_DIR/rt_demo"
