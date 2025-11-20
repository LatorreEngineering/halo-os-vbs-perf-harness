#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# Use WORKSPACE env variable or fallback to current directory
WORKSPACE="${WORKSPACE:-$(pwd)}"
MANIFEST_DIR="$WORKSPACE/manifests"
MANIFEST_FILE="$MANIFEST_DIR/manifest_20250825.xml"

# Ensure manifest directory exists
mkdir -p "$MANIFEST_DIR"

# Download manifest from Gitee if missing
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Downloading manifest_20250825.xml from Gitee..."
    if [ -z "${GITEE_TOKEN:-}" ]; then
        echo "⚠️ Warning: GITEE_TOKEN not set, attempting anonymous download"
        curl -fSL -o "$MANIFEST_FILE" "https://gitee.com/haloos/manifests/raw/main/manifest_20250825.xml"
    else
        curl -fSL -u "oauth2:${GITEE_TOKEN}" -o "$MANIFEST_FILE" \
            "https://gitee.com/haloos/manifests/raw/main/manifest_20250825.xml"
    fi
fi

# Ensure repo tool is available
if ! command -v repo >/dev/null 2>&1; then
    echo "❌ repo tool not found in PATH"
    exit 1
fi

# Initialize repo inside WORKSPACE
REPO_DIR="$WORKSPACE/repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

# Repo init with Gitee manifest
echo "Initializing repo..."
if [ -z "${GITEE_TOKEN:-}" ]; then
    repo init -u https://gitee.com/haloos/manifest.git -m "$MANIFEST_FILE" --quiet
else
    # Use HTTPS with token to avoid authentication errors
    REPO_URL="https://oauth2:${GITEE_TOKEN}@gitee.com/haloos/manifest.git"
    repo init -u "$REPO_URL" -m "$MANIFEST_FILE" --quiet
fi

# Sync repo
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
    echo "❌ No toolchain file found. Please add one to $WORKSPACE/toolchains/"
    exit 1
fi

# Build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
make -j"$(nproc)"

echo "=== Build complete ==="
echo "Executable located at $BUILD_DIR/rt_demo"
