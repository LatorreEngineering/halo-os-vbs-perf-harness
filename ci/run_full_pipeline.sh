#!/usr/bin/env bash
set -euo pipefail

echo "=== Halo.OS Full Pipeline ==="

# Step 1: Build the instrumented demo
echo "--- Step 1: Building Halo.OS demo ---"
./ci/build_halo.sh

# Step 2: Detect hardware
echo "--- Step 2: Detecting hardware ---"
HARDWARE="host"

if [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model)
    if [[ "$MODEL" == *"Jetson"* ]]; then
        HARDWARE="jetson"
    fi
elif lspci | grep -i nvidia >/dev/null 2>&1; then
    HARDWARE="jetson"
fi

echo "Detected hardware: $HARDWARE"

# Step 3: Run experiment
echo "--- Step 3: Running experiment ---"
OUT_DIR="results/run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"

if [ "$HARDWARE" == "jetson" ]; then
    echo "Running real hardware experiment (Jetson)..."
    ./ci/run_experiment_hw.sh "$OUT_DIR" 300
else
    echo "Running simulation experiment (host/x86)..."
    ./ci/run_experiment.sh "$OUT_DIR" 300
fi

# Step 4: Analyze results
echo "--- Step 4: Analyzing results ---"
python3 ci/analyze.py "$OUT_DIR/events.jsonl"

echo "=== Pipeline complete. Artifacts stored in $OUT_DIR ==="
