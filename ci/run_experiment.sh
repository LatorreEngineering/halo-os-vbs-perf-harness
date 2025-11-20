#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <output_dir> <num_samples>"
    exit 1
fi

OUTDIR="$1"
NUM_SAMPLES="$2"

# Make sure workspace output directory exists
mkdir -p "$OUTDIR"

echo "=== Running VBS experiment ==="
echo "Output directory: $OUTDIR"
echo "Number of samples: $NUM_SAMPLES"

# Simulated experiment loop (replace with real experiment commands)
for i in $(seq 1 "$NUM_SAMPLES"); do
    RUN_DIR="$OUTDIR/run_$i"
    mkdir -p "$RUN_DIR"
    # Here you would run the real VBS commands, logs, etc.
    echo "{\"frame_id\": $i, \"name\": \"halo_camera_ingest\", \"time\": $(date +%s%N)}" > "$RUN_DIR/events.jsonl"
    echo "{\"frame_id\": $i, \"name\": \"halo_brake_actuate\", \"time\": $(date +%s%N)}" >> "$RUN_DIR/events.jsonl"
done

echo "=== Experiment completed ==="
