#!/usr/bin/env python3
"""
analyze_vbs.py - Modular performance analysis for Halo.OS VBS traces with frame_id alignment.

Usage:
    python analyze_vbs.py --trace <trace_dir> --output <output_dir> \
                          [--start_event halo_camera_ingest] \
                          [--end_event halo_brake_actuate]
"""

import argparse
from pathlib import Path
import pandas as pd
import numpy as np
import json
import matplotlib.pyplot as plt
import sys

def load_lttng(dir_path: Path, event_prefix: str = "halo_") -> pd.DataFrame:
    """
    Load all LTTng log files in a directory and filter events by prefix.

    Args:
        dir_path (Path): Directory containing log files.
        event_prefix (str): Prefix of events to include.

    Returns:
        pd.DataFrame: DataFrame of events.
    """
    if not dir_path.exists() or not dir_path.is_dir():
        raise FileNotFoundError(f"Trace directory not found: {dir_path}")
    
    events = []
    for f in dir_path.rglob("*.log"):
        with open(f, "r") as file:
            for line in file:
                if event_prefix in line:
                    try:
                        payload = eval(line.split(" ", 1)[1])
                        events.append(payload)
                    except Exception as e:
                        print(f"[WARN] Skipping malformed line in {f}: {line.strip()} ({e})")
    if not events:
        raise ValueError(f"No events found with prefix '{event_prefix}' in {dir_path}")
    return pd.DataFrame(events)

def compute_latency(df: pd.DataFrame, start_event: str, end_event: str) -> pd.Series:
    """
    Compute latency (ms) between two events using frame_id alignment.

    Args:
        df (pd.DataFrame): Event DataFrame.
        start_event (str): Name of start event.
        end_event (str): Name of end event.

    Returns:
        pd.Series: Latency in milliseconds.
    """
    try:
        ingest = df[df['name'] == start_event].set_index('frame_id')['time']
        actuate = df[df['name'] == end_event].set_index('frame_id')['time']
    except KeyError as e:
        raise KeyError(f"Missing required columns in DataFrame: {e}")
    
    common_frames = ingest.index.intersection(actuate.index)
    if common_frames.empty:
        raise ValueError(f"No matching frame_ids found between {start_event} and {end_event}")
    
    lat_ms = (actuate.loc[common_frames] - ingest.loc[common_frames]) / 1e6
    return lat_ms

def compute_jitter(latencies: pd.Series) -> float:
    """
    Compute jitter as std deviation of latencies (ms).

    Args:
        latencies (pd.Series): Latency values.

    Returns:
        float: Jitter in ms.
    """
    return float(np.std(latencies))

def analyze_npu(dir_path: Path) -> float:
    """
    Compute NPU/GPU overhead from tegrastats.log.

    Args:
        dir_path (Path): Directory containing tegrastats.log.

    Returns:
        float: NPU/GPU utilization overhead (%), or None if log missing.
    """
    npu_file = dir_path / "tegrastats.log"
    if not npu_file.exists():
        return None
    try:
        npu = pd.read_csv(npu_file, delim_whitespace=True, comment="#",
                          header=None, names=["time","cpu","gpu","gr3d"])
        overhead = 100 - (npu['gr3d'].mean() / npu['gr3d'].max() * 100)
        return float(overhead)
    except Exception as e:
        print(f"[WARN] Failed to analyze NPU log: {e}")
        return None

def generate_plots(latencies: pd.Series, output_dir: Path) -> None:
    """
    Generate histogram plot for latency.

    Args:
        latencies (pd.Series): Latency values (ms)
        output_dir (Path): Directory to save plot.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(8, 5))
    plt.hist(latencies, bins=30, color='skyblue', edgecolor='black')
    plt.title("Latency Distribution")
    plt.xlabel("Latency (ms)")
    plt.ylabel("Frequency")
    plt.grid(True)
    plt.tight_layout()
    plot_file = output_dir / "latency_histogram.png"
    plt.savefig(plot_file)
    plt.close()
    print(f"[INFO] Plot saved to {plot_file}")

def save_results(latencies: pd.Series, overhead: float, output_dir: Path) -> None:
    """
    Save latency metrics and NPU overhead to JSON.

    Args:
        latencies (pd.Series): Latency values.
        overhead (float): NPU/GPU overhead (%), or None.
        output_dir (Path): Directory to save results.
    """
    results = {
        "num_samples": int(len(latencies)),
        "mean_latency_ms": float(latencies.mean()),
        "p50_latency_ms": float(latencies.quantile(0.50)),
        "p99_99_jitter_ms": float(latencies.quantile(0.9999) - latencies.quantile(0.50)),
        "npu_overhead_percent": overhead
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    result_file = output_dir / "latency_results.json"
    with open(result_file, "w") as f:
        json.dump(results, f, indent=4)
    print(f"[INFO] Results saved to {result_file}")

def main():
    parser = argparse.ArgumentParser(description="Halo.OS VBS Performance Analyzer")
    parser.add_argument("--trace", required=True, type=Path, help="Input trace directory")
    parser.add_argument("--output", required=True, type=Path, help="Output directory")
    parser.add_argument("--start_event", default="halo_camera_ingest", help="Start event name")
    parser.add_argument("--end_event", default="halo_brake_actuate", help="End event name")
    args = parser.parse_args()

    try:
        df = load_lttng(args.trace)
        latencies = compute_latency(df, args.start_event, args.end_event)
        overhead = analyze_npu(args.trace)
        generate_plots(latencies, args.output)
        save_results(latencies, overhead, args.output)

        # Print summary to stdout
        print(f"Samples: {len(latencies)}")
        print(f"Mean latency : {latencies.mean():.2f} ms")
        print(f"P50          : {latencies.quantile(0.50):.2f} ms")
        print(f"P99.99 jitter: {(latencies.quantile(0.9999) - latencies.quantile(0.50)):.2f} ms")
        if overhead is not None:
            print(f"NPU/GPU utilization overhead: {overhead:.2f}%")

    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()

