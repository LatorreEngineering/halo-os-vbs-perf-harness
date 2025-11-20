#!/usr/bin/env bash
set -euo pipefail

OUT_DIR=${1:-results/run_hw_$(date +%Y%m%d_%H%M%S)}
DURATION=${2:-300}  # default runtime in seconds

mkdir -p "$OUT_DIR"
echo "=== Running Halo.OS real hardware experiment ==="
echo "Output directory: $OUT_DIR"
echo "Duration: $DURATION seconds"

# Step 1: Start LTTng tracing (UST user/kernel events)
SESSION="halo_hw_$(date +%Y%m%d_%H%M%S)"
lttng create "$SESSION" -o "$OUT_DIR/lttng"
lttng enable-event -u halo:*
lttng enable-event -k sched_switch,irq_handler_entry,irq_handler_exit
lttng start

# Step 2: Start Ethernet / VBS capture
sudo tcpdump -i eth0 -w "$OUT_DIR/vbs_traffic.pcap" -s 256 &
TCPDUMP_PID=$!

# Step 3: Start NPU telemetry (Jetson)
if command -v tegrastats >/dev/null; then
    tegrastats --interval 100 --logfile "$OUT_DIR/tegrastats.log" &
    TEGRA_PID=$!
fi

# Step 4: Run the Halo.OS demo
echo "=== Starting real hardware 120 km/h AEB workload ==="
./build/apps/rt_demo --scenario aeb_120kph --duration "$DURATION"

# Step 5: Stop telemetry
kill $TCPDUMP_PID 2>/dev/null || true
kill ${TEGRA_PID:-} 2>/dev/null || true

# Step 6: Stop LTTng session
lttng stop
lttng destroy

# Step 7: Final message
echo "=== Real hardware experiment complete ==="
echo "Artifacts stored in: $OUT_DIR"
echo "You can now analyze results with: python3 ci/analyze.py $OUT_DIR/events.jsonl"
