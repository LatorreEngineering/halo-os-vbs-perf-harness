#!/usr/bin/env bash
set -euo pipefail

RUN=${1:-hw_run}
DURATION=${2:-60}
OUT=results/$RUN
mkdir -p "$OUT"

# Environment dump
./ci/env_dump.sh "$OUT/env.txt"

echo "=== Running Halo.OS AEB workload on real hardware ==="
timeout "$((DURATION + 10))" ./build/apps/rt_demo --scenario aeb_120kph --duration "$DURATION"

# Capture traces
lttng stop
lttng destroy
echo "=== Done, traces saved in $OUT ==="
