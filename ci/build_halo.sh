#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# Check for pinned manifest
MANIFEST_FILE="manifests/pinned_manifest.xml"
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Error: $MANIFEST_FILE not found!"
    exit 1
fi

# Initialize repo with pinned manifest
repo init -u https://gitee.com/haloos/manifest.git -m "$MANIFEST_FILE"
repo sync --force-sync

# Build instrumented demo
DEMO_DIR="apps/rt_demo"
BUILD_DIR="$DEMO_DIR/build"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Select toolchain based on environment
if [ -f "../../toolchains/jetson.cmake" ]; then
    TOOLCHAIN_FILE="../../toolchains/jetson.cmake"
    echo "Using Jetson toolchain"
elif [ -f "../../toolchains/host.cmake" ]; then
    TOOLCHAIN_FILE="../../toolchains/host.cmake"
    echo "Using host/x86 toolchain"
else
    echo "No toolchain file found. Please add one to toolchains/ directory."
    exit 1
fi

cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
make -j$(nproc)

echo "=== Build complete ==="
echo "Executable located at $BUILD_DIR/rt_demo"
