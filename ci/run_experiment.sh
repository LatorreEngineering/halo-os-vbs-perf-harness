#!/usr/bin/env bash
set -euo pipefail

RUN=${1:-testrun}
DURATION=${2:-300}   # default 300 seconds
OUT=results/$RUN
mkdir -p "$OUT"

echo "=== Running Halo.OS perf experiment: $RUN for $DURATION seconds ==="

# Create LTTng session
lttng create "$RUN" -o "$OUT/lttng"
lttng enable-event -u halo:*
lttng enable-event -k sched_switch,irq_handler_entry,irq_handler_exit
lttng start

# NVIDIA telemetry (Jetson only)
if command -v tegrastats &>/dev/null; then
    tegrastats --interval 100 --logfile "$OUT/tegrastats.log" &
    TEGRA_PID=$!
fi

# Network traffic capture (optional)
tcpdump -i any -w "$OUT/traffic.pcap" -s 256 &
TCPDUMP_PID=$!

# Run demo workload
echo "=== Starting 120 km/h AEB workload ==="
timeout "$((DURATION + 10))" ./build/apps/rt_demo --scenario aeb_120kph --duration "$DURATION"

# Cleanup
kill ${TEGRA_PID:-} ${TCPDUMP_PID:-} 2>/dev/null || true
lttng stop
lttng destroy

echo "=== Experiment complete. Artifacts stored in $OUT ==="
