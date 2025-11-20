#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# Use WORKSPACE env variable or default to current directory
WORKSPACE="${WORKSPACE:-$(pwd)}"
MANIFEST_DIR="$WORKSPACE/manifests"
REPO_DIR="$WORKSPACE/repo"
mkdir -p "$MANIFEST_DIR"

# -------------------------------
# Select manifest file to use
# -------------------------------
MANIFEST_FILE="$MANIFEST_DIR/manifest_20250825.xml"
MANIFEST_URL="https://gitee.com/haloos/manifests/raw/main/manifest_20250825.xml"
DEFAULT_MANIFEST_FILE="$MANIFEST_DIR/default.xml"
DEFAULT_MANIFEST_URL="https://gitee.com/haloos/manifests/raw/main/default.xml"

# -------------------------------
# Download manifest
# -------------------------------
download_manifest() {
    local file="$1"
    local url="$2"
    if [ -n "${GITEE_TOKEN:-}" ]; then
        curl -fsSL -H "Authorization: token $GITEE_TOKEN" -o "$file" "$url"
    else
        curl -fsSL -o "$file" "$url"
    fi
}

echo "Downloading manifest_20250825.xml from Halo.OS Gitee..."
if ! download_manifest "$MANIFEST_FILE" "$MANIFEST_URL"; then
    echo "⚠️ manifest_20250825.xml not found, falling back to default.xml"
    if ! download_manifest "$DEFAULT_MANIFEST_FILE" "$DEFAULT_MANIFEST_URL"; then
        echo "❌ Failed to download default.xml as fallback"
        exit 1
    fi
    MANIFEST_FILE="$DEFAULT_MANIFEST_FILE"
fi

# -------------------------------
# Initialize repo
# -------------------------------
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

# Ensure 'repo' is installed
if ! command -v repo &> /dev/null; then
    echo "❌ 'repo' tool not found. Make sure setup_env.sh ran correctly."
    exit 1
fi

# Prepare authenticated URL if token is available
REPO_URL="https://gitee.com/haloos/manifest.git"
if [ -n "${GITEE_TOKEN:-}" ]; then
    REPO_URL="https://$GITEE_TOKEN@e.gitee.com/haloos/manifest.git"
fi

# Initialize and sync repo
echo "Initializing repo with $MANIFEST_FILE..."
repo init -u "$REPO_URL" -m "$MANIFEST_FILE" --quiet
echo "Syncing repo..."
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

# Build using CMake
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
make -j"$(nproc)"

echo "=== Build complete ==="
echo "Executable located at $BUILD_DIR/rt_demo"
