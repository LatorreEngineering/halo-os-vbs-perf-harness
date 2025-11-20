#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# Use WORKSPACE env variable or default to current directory
WORKSPACE="${WORKSPACE:-$(pwd)}"
MANIFEST_DIR="$WORKSPACE/manifests"
MANIFEST_FILE="$MANIFEST_DIR/pinned_manifest.xml"

# Create manifests directory if missing
mkdir -p "$MANIFEST_DIR"

# Download the pinned manifest if it doesn't exist
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Downloading pinned_manifest.xml from Gitee..."
    curl -L -o "$MANIFEST_FILE" "https://gitee.com/haloos/manifest/raw/main/pinned_manifest.xml"
fi

# Initialize repo inside WORKSPACE
REPO_DIR="$WORKSPACE/repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

repo init -u https://gitee.com/haloos/manifest.git -m "$MANIFEST_FILE" --repo-dir="$REPO_DIR" --quiet
repo sync --force-sync --quiet

# Build instrumented demo
DEMO_DIR="$REPO_DIR/apps/rt_demo"
BUILD_DIR="$DEMO_DIR/build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Select toolchain
if [ -f "$WORKSPACE/toolchains/jetson.cmake" ]; then
    TOOLCHAIN_FILE="$WORKSPACE/toolchains/jetson.cmake"
    echo "Using Jetson toolchain"
elif [ -f "$WORKSPACE/toolchains/host.cmake" ]; then
    TOOLCHAIN_FILE="$WORKSPACE/toolchains/host.cmake"
    echo "Using host/x86 toolchain"
else
    echo "No toolchain file found. Please add one to $WORKSPACE/toolchains/"
    exit 1
fi

cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
make -j"$(nproc)"

echo "=== Build complete ==="
echo "Executable located at $BUILD_DIR/rt_demo"
