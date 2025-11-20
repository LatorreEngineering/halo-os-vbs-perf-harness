#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# Ensure WORKSPACE is defined
WORKSPACE="${WORKSPACE:-$(pwd)}"

# Manifest setup
MANIFEST_DIR="$WORKSPACE/manifests"
MANIFEST_FILE="$MANIFEST_DIR/manifest_20250825.xml"
mkdir -p "$MANIFEST_DIR"

# Download the manifest if missing
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Downloading manifest_20250825.xml from Gitee..."
    curl -L -o "$MANIFEST_FILE" "https://gitee.com/haloos/manifests/raw/main/manifest_20250825.xml"
fi

# Ensure GITEE_TOKEN is set
: "${GITEE_TOKEN:?GITEE_TOKEN secret must be set in GitHub Actions}"

# Initialize repo inside WORKSPACE
REPO_DIR="$WORKSPACE/repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

# Use token in HTTPS URL for authentication
REPO_URL="https://${GITEE_TOKEN}@gitee.com/haloos/manifest.git"

echo "Initializing repo..."
repo init -u "$REPO_URL" -m "$MANIFEST_FILE" --quiet

echo "Syncing repo..."
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
    echo "No toolchain file found in $WORKSPACE/toolchains/"
    exit 1
fi

cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
make -j"$(nproc)"

echo "=== Build complete ==="
echo "Executable located at $BUILD_DIR/rt_demo"

