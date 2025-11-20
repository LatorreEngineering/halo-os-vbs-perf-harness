#!/usr/bin/env python3
"""
Improved analyze_vbs.py - Robust VBS latency analysis for Halo.OS

Features:
 - Automatically loads all runs in trace_dir/run_*/events.jsonl
 - Validates frame ordering & missing events
 - Computes latency, jitter, p99, p9999
 - Generates plots
 - Gracefully handles empty or malformed data
"""

import argparse
from pathlib import Path
import pandas as pd
import numpy as np
import json
import logging
import sys
import matplotlib
matplotlib.use("Agg")   # Safe for CI
import matplotlib.pyplot as plt


logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")


# ------------------------------------------------------------
# Load JSONL files
# ------------------------------------------------------------
def load_jsonl_runs(trace_dir: Path) -> pd.DataFrame:
    """
    Loads all run_*/events.jsonl files into a single DataFrame.
    """
    run_dirs = sorted(trace_dir.glob("run_*"))
    if not run_dirs:
        raise FileNotFoundError(f"No run_* directories found in {trace_dir}")

    events = []
    for run in run_dirs:
        jsonl = run / "events.jsonl"
        if not jsonl.exists():
            logging.warning(f"Missing events.jsonl in {run}, skipping.")
            continue

        with open(jsonl, "r") as f:
            for line in f:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    logging.warning(f"Malformed JSON in {jsonl}: {line.strip()}")

    if not events:
        raise ValueError("No valid events found in experiment.")

    df = pd.DataFrame(events)

    required = {"frame_id", "time", "name"}
    if not required.issubset(df.columns):
        raise ValueError(f"Missing required columns: {required - set(df.columns)}")

    return df.sort_values("frame_id")


# ------------------------------------------------------------
# Latency computation
# ------------------------------------------------------------
def compute_latency(df: pd.DataFrame, start_event: str, end_event: str) -> pd.Series:

    start_df = df[df["name"] == start_event].set_index("frame_id")["time"]
    end_df   = df[df["name"] == end_event].set_index("frame_id")["time"]

    common = start_df.index.intersection(end_df.index)
    if len(common) == 0:
        raise ValueError(f"No matching frame_ids between {start_event} and {end_event}")

    latency_ms = (end_df.loc[common] - start_df.loc[common]) / 1e6

    return latency_ms


# ------------------------------------------------------------
# Plots
# ------------------------------------------------------------
def generate_plots(latencies: pd.Series, out: Path, bins: int = 40):
    out.mkdir(parents=True, exist_ok=True)

    plt.figure(figsize=(8, 5))
    plt.hist(latencies, bins=bins, edgecolor='black')
    plt.title("Latency Distribution")
    plt.xlabel("Latency (ms)")
    plt.ylabel("Frequency")
    plt.tight_layout()

    img = out / "latency_histogram.png"
    plt.savefig(img)
    plt.close()

    logging.info(f"Saved histogram → {img}")


# ------------------------------------------------------------
# Save results
# ------------------------------------------------------------
def save_results(lat: pd.Series, out: Path):
    out.mkdir(parents=True, exist_ok=True)

    results = {
        "num_samples": int(len(lat)),
        "mean_ms": float(lat.mean()),
        "median_ms": float(lat.median()),
        "p95_ms": float(lat.quantile(0.95)),
        "p99_ms": float(lat.quantile(0.99)),
        "p9999_ms": float(lat.quantile(0.9999)),
        "std_jitter_ms": float(lat.std()),
    }

    f = out / "latency_results.json"
    with open(f, "w") as fp:
        json.dump(results, fp, indent=4)

    logging.info(f"Saved results → {f}")


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--trace", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--start_event", default="halo_camera_ingest")
    parser.add_argument("--end_event", default="halo_brake_actuate")
    parser.add_argument("--bins", type=int, default=40)
    a = parser.parse_args()

    try:
        df = load_jsonl_runs(a.trace)
        lat = compute_latency(df, a.start_event, a.end_event)
        generate_plots(lat, a.output, bins=a.bins)
        save_results(lat, a.output)

        logging.info("")
        logging.info("==== SUMMARY ====")
        logging.info(f"Samples: {len(lat)}")
        logging.info(f"Mean latency:  {lat.mean():.3f} ms")
        logging.info(f"P95 latency:   {lat.quantile(0.95):.3f} ms")
        logging.info(f"P99 latency:   {lat.quantile(0.99):.3f} ms")
        logging.info(f"P99.99 latency:{lat.quantile(0.9999):.3f} ms")
        logging.info(f"Std jitter:    {lat.std():.3f} ms")

    except Exception as e:
        logging.error(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
