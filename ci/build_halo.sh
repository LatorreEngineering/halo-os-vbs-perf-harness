#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# Use WORKSPACE env variable or default to current directory
WORKSPACE="${WORKSPACE:-$(pwd)}"
MANIFEST_DIR="$WORKSPACE/manifests"
REPO_DIR="$WORKSPACE/repo"

# -------------------------------
# Select manifest file to use
# -------------------------------
MANIFEST_FILE="$MANIFEST_DIR/manifest_20250825.xml"
mkdir -p "$MANIFEST_DIR"

# Download manifest if missing
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Downloading manifest_20250825.xml from Halo.OS Gitee..."
    curl -fsSL -o "$MANIFEST_FILE" "https://gitee.com/haloos/manifests/raw/main/manifest_20250825.xml"
fi

# -------------------------------
# Initialize repo
# -------------------------------
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

# Make sure 'repo' command is available
if ! command -v repo &> /dev/null; then
    echo "❌ 'repo' tool not found. Make sure setup_env.sh ran correctly."
    exit 1
fi

# Init and sync repo
repo init -u https://gitee.com/haloos/manifest.git -m "$MANIFEST_FILE" --quiet
repo sync --force-sync --quiet

# -------------------------------
# Build instrumented demo
# -------------------------------
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
    echo "❌ No toolchain file found. Please add one to $WORKSPACE/toolchains/"
    exit 1
fi

cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
make -j"$(nproc)"

echo "=== Build complete ==="
echo "Executable located at $BUILD_DIR/rt_demo"
