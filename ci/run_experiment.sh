#!/usr/bin/env bash
set -euo pipefail

#############################################
# Argument parsing & validation
#############################################
if [ $# -lt 2 ]; then
    echo "Usage: $0 <output_dir> <num_samples> [--random-latency]"
    exit 1
fi

OUTDIR="$1"
NUM_SAMPLES="$2"
RANDOM_LATENCY=false

if ! [[ "$NUM_SAMPLES" =~ ^[0-9]+$ ]] || [ "$NUM_SAMPLES" -le 0 ]; then
    echo "❌ num_samples must be a positive integer"
    exit 1
fi

if [ "${3:-}" == "--random-latency" ]; then
    RANDOM_LATENCY=true
fi

mkdir -p "$OUTDIR"

echo "=== Running VBS experiment ==="
echo "Output directory: $OUTDIR"
echo "Number of samples: $NUM_SAMPLES"
echo "Random latency enabled: $RANDOM_LATENCY"
echo

#############################################
# Metadata file
#############################################
METADATA_FILE="$OUTDIR/experiment_metadata.json"

cat > "$METADATA_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "num_samples": $NUM_SAMPLES,
  "random_latency": $RANDOM_LATENCY,
  "hostname": "$(hostname)",
  "generator_version": "v1.2"
}
EOF

echo "[INFO] Metadata saved to $METADATA_FILE"

#############################################
# Trap for clean exit
#############################################
cleanup() {
    echo "⚠️ Experiment interrupted"
    exit 1
}
trap cleanup INT TERM

#############################################
# Main experiment loop
#############################################
for i in $(seq 1 "$NUM_SAMPLES"); do
    RUN_DIR="$OUTDIR/run_$i"
    mkdir -p "$RUN_DIR"

    # Start timestamp in nanoseconds
    START_TS=$(date +%s%N)

    # Optional simulated latency
    if [ "$RANDOM_LATENCY" = true ]; then
        LAT_MS=$((RANDOM % 8))
        # Sleep in seconds; supports sub-second fractional sleep
        sleep "$(awk "BEGIN {printf \"%.3f\", $LAT_MS/1000}")"
    else
        # Fixed 1ms latency for deterministic runs
        sleep 0.001 || true
    fi

    END_TS=$(date +%s%N)

    # Generate JSONL events
    EVENTS_FILE="$RUN_DIR/events.jsonl"
    {
        echo "{\"frame_id\": $i, \"name\": \"halo_camera_ingest\", \"time\": $START_TS}"
        echo "{\"frame_id\": $i, \"name\": \"halo_brake_actuate\", \"time\": $END_TS}"
    } > "$EVENTS_FILE"

    # Logging
    LAT_US=$(( (END_TS - START_TS) / 1000 ))
    echo "[INFO] Sample $i generated, latency=${LAT_US}µs, saved to $EVENTS_FILE"
done

echo
echo "=== Experiment completed successfully ==="
