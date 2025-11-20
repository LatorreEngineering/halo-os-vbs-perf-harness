#!/usr/bin/env bash
set -euo pipefail

echo "=== Building instrumented Halo.OS demo ==="

# Use WORKSPACE env variable or default to current directory
WORKSPACE="${WORKSPACE:-$(pwd)}"
MANIFEST_DIR="$WORKSPACE/manifests"
MANIFEST_FILE="$MANIFEST_DIR/default.xml"

# Create manifests directory if missing
mkdir -p "$MANIFEST_DIR"

# Download the default manifest if it doesn't exist
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Downloading default.xml from Halo.OS manifest repo..."
    curl -L -o "$MANIFEST_FILE" "https://gitee.com/haloos/manifests/raw/main/default.xml"
fi

# Initialize repo inside WORKSPACE
REPO_DIR="$WORKSPACE/repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

# Make sure 'repo' is installed
if ! command -v repo &> /dev/null; then
    echo "❌ ERROR: 'repo' command not found. Please install repo first."
    exit 1
fi

repo init -u https://gitee.com/haloos/manifests.git -m "$MANIFEST_FILE" --repo-dir="$REPO_DIR" --quiet
repo sync --force-sync --quiet

# Build instrumented demo
DEMO_DIR="$REPO_DIR/apps/rt_demo"
BUILD_DIR="$DEMO_DIR/build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Select toolchain
if [ -f "$WORKSPACE/toolchains/jetson.cmake" ]; then
    TOOLCHAIN_FILE="$WORKSPACE/toolchains/jetson.cm_

