#!/usr/bin/env bash
set -euo pipefail

RUN=${1:-hw_run}
DURATION=${2:-60}
OUT=results/$RUN
mkdir -p "$OUT"

# Dump environment info
./ci/env_dump.sh "$OUT/env.txt"

echo "=== Running Halo.OS AEB workload on real hardware ==="

# Start LTTng session
lttng create "$RUN" -o "$OUT/lttng"
lttng enable-event -u halo:*
lttng enable-event -k sched_switch,irq_handler_entry,irq_handler_exit
lttng start

# NVIDIA Jetson telemetry (if available)
if command -v tegrastats >/dev/null; then
  tegrastats --interval 100 --logfile "$OUT/tegrastats.log" &
  TEGRA_PID=$!
fi

# Capture Ethernet / VBS traffic
sudo tcpdump -i any -w "$OUT/traffic.pcap" -s 256 &
TCPDUMP_PID=$!

# Run AEB demo (safely, HIL preferred)
timeout "$((DURATION + 10))" ./build/apps/rt_demo --scenario aeb_120kph --duration "$DURATION"

# Stop telemetry
kill ${TEGRA_PID:-0} ${TCPDUMP_PID:-0} 2>/dev/null || true
lttng stop
lttng destroy

echo "=== Done – traces saved in $OUT ==="
