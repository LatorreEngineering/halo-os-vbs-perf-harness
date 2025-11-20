#!/usr/bin/env bash
set -euo pipefail

echo "=== Building Halo.OS instrumented demo ==="

BUILD_DIR=build
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# CMake build (adjust toolchain if on Jetson or other ARM)
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

echo "=== Build complete ==="
