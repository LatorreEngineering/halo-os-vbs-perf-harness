#!/usr/bin/env python3
"""
analyze_vbs.py - Robust Halo.OS VBS latency analysis

Features:
 - Loads all run_*/events.jsonl from trace_dir
 - Computes latency, jitter, P95, P99, P99.99
 - Generates histogram
 - Outputs results as JSON compatible with CI
"""

import argparse
from pathlib import Path
import pandas as pd
import numpy as np
import json
import logging
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")


# ------------------------------------------------------------
# Load all JSONL runs
# ------------------------------------------------------------
def load_jsonl_runs(trace_dir: Path) -> pd.DataFrame:
    run_dirs = sorted(trace_dir.glob("run_*"))
    if not run_dirs:
        raise FileNotFoundError(f"No run_* directories found in {trace_dir}")

    events = []
    for run in run_dirs:
        jsonl_file = run / "events.jsonl"
        if not jsonl_file.exists():
            logging.warning(f"Missing {jsonl_file}, skipping")
            continue
        with open(jsonl_file) as f:
            for line in f:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    logging.warning(f"Malformed JSON: {line.strip()}")

    if not events:
        raise ValueError("No valid events found")

    df = pd.DataFrame(events)
    required = {"frame_id", "time", "name"}
    if not required.issubset(df.columns):
        raise ValueError(f"Missing required columns: {required - set(df.columns)}")

    return df.sort_values("frame_id")


# ------------------------------------------------------------
# Compute latency
# ------------------------------------------------------------
def compute_latency(df: pd.DataFrame, start_event: str, end_event: str) -> pd.Series:
    start_df = df[df["name"] == start_event].set_index("frame_id")["time"]
    end_df = df[df["name"] == end_event].set_index("frame_id")["time"]

    common_frames = start_df.index.intersection(end_df.index)
    if len(common_frames) == 0:
        raise ValueError(f"No matching frame_ids between {start_event} and {end_event}")

    latency_ms = (end_df.loc[common_frames] - start_df.loc[common_frames]) / 1e6
    return latency_ms


# ------------------------------------------------------------
# Generate histogram
# ------------------------------------------------------------
def generate_plots(latencies: pd.Series, out_dir: Path, bins: int = 30):
    out_dir.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(8, 5))
    plt.hist(latencies, bins=bins, edgecolor='black', color='skyblue')
    plt.title("Latency Distribution")
    plt.xlabel("Latency (ms)")
    plt.ylabel("Frequency")
    plt.tight_layout()
    plot_file = out_dir / "latency_histogram.png"
    plt.savefig(plot_file)
    plt.close()
    logging.info(f"Saved histogram → {plot_file}")


# ------------------------------------------------------------
# Save results JSON
# ------------------------------------------------------------
def save_results(latencies: pd.Series, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    results = {
        "num_samples": int(len(latencies)),
        "mean_latency_ms": float(latencies.mean()),
        "p50_latency_ms": float(latencies.quantile(0.50)),
        "p95_latency_ms": float(latencies.quantile(0.95)),
        "p99_latency_ms": float(latencies.quantile(0.99)),
        "p9999_latency_ms": float(latencies.quantile(0.9999)),
        "std_jitter_ms": float(latencies.std())
    }

    json_file = out_dir / "latency_results.json"
    with open(json_file, "w") as f:
        json.dump(results, f, indent=4)
    logging.info(f"Saved results → {json_file}")


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--trace", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--start_event", default="halo_camera_ingest")
    parser.add_argument("--end_event", default="halo_brake_actuate")
    parser.add_argument("--bins", type=int, default=30)
    args = parser.parse_args()

    try:
        df = load_jsonl_runs(args.trace)
        latencies = compute_latency(df, args.start_event, args.end_event)
        generate_plots(latencies, args.output, bins=args.bins)
        save_results(latencies, args.output)

        logging.info("\n==== SUMMARY ====")
        logging.info(f"Samples: {len(latencies)}")
        logging.info(f"Mean latency:  {latencies.mean():.3f} ms")
        logging.info(f"P50 latency:   {latencies.quantile(0.50):.3f} ms")
        logging.info(f"P95 latency:   {latencies.quantile(0.95):.3f} ms")
        logging.info(f"P99 latency:   {latencies.quantile(0.99):.3f} ms")
        logging.info(f"P99.99 latency:{latencies.quantile(0.9999):.3f} ms")
        logging.info(f"Std jitter:    {latencies.std():.3f} ms")

    except Exception as e:
        logging.error(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
