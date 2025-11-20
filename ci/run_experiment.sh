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

cat > "$OUTDIR/experiment_metadata.json" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "num_samples": $NUM_SAMPLES,
  "random_latency": $RANDOM_LATENCY,
  "hostname": "$(hostname)",
  "generator_version": "v1.1"
}
EOF

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

    # Start event timestamp
    START_TS=$(date +%s%N)

    # Optional simulated latency
    if [ "$RANDOM_LATENCY" = true ]; then
        # random 0–8ms latency
        LAT_MS=$((RANDOM % 8))
        sleep "0.$LAT_MS"
    else
        # fixed 1ms latency for deterministic CI runs
        sleep 0.001
    fi

    END_TS=$(date +%s%N)

    # JSONL output
    {
        echo "{\"frame_id\": $i, \"name\": \"halo_camera_ingest\", \"time\": $START_TS}"
        echo "{\"frame_id\": $i, \"name\": \"halo_brake_actuate\", \"time\": $END_TS}"
    } > "$RUN_DIR/events.jsonl"

    # logging
    printf "Generated sample %d: latency=%dus\n" "$i" "$(( (END_TS - START_TS) / 1000 ))"
done

echo
echo "=== Experiment completed successfully ==="
