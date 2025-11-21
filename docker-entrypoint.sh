#!/bin/bash
# docker-entrypoint.sh
# Purpose: Initialize Docker container environment for Halo.OS development

set -e

echo "========================================"
echo "Halo.OS Performance Harness Container"
echo "========================================"

# Display environment information
echo "User: $(whoami)"
echo "Working directory: $(pwd)"
echo "Python version: $(python3 --version)"
echo "CMake version: $(cmake --version | head -n1)"

# Create necessary directories
mkdir -p "${BUILD_DIR}" "${RESULTS_DIR}" logs cache

# Display available commands
if [ "$1" = "/bin/bash" ] || [ -z "$1" ]; then
    echo ""
    echo "Available commands:"
    echo "  ./ci/setup_env.sh      - Install dependencies"
    echo "  ./ci/build_halo.sh     - Build Halo.OS"
    echo "  ./ci/run_experiment.sh - Run experiments"
    echo "  python3 ci/analyze_vbs.py - Analyze results"
    echo ""
    echo "Ready for development!"
    echo "========================================"
fi

# Execute the command
exec "$@"
