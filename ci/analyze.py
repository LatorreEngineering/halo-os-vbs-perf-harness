#!/usr/bin/env python3
"""
analyze_vbs.py - Modular performance analysis for Halo.OS VBS traces.

This script parses LTTng trace data, computes latency and jitter metrics,
and generates reports/plots for analysis.

Usage:
    python analyze_vbs.py --input sample_events.jsonl --output results/
"""

import argparse
import json
import os
from typing import List, Dict, Tuple
import matplotlib.pyplot as plt
import numpy as np


def parse_trace(file_path: str) -> List[Dict]:
    """
    Parse a JSONL trace file into a list of events.

    Args:
        file_path (str): Path to JSONL trace file.

    Returns:
        List[Dict]: List of event dictionaries.
    """
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Trace file not found: {file_path}")
    
    events = []
    with open(file_path, 'r') as f:
        for line in f:
            events.append(json.loads(line.strip()))
    return events


def compute_latency(events: List[Dict], start_event: str, end_event: str) -> List[float]:
    """
    Compute latency between two types of events.

    Args:
        events (List[Dict]): Parsed event list.
        start_event (str): Name of the start event.
        end_event (str): Name of the end event.

    Returns:
        List[float]: Latencies in milliseconds.
    """
    start_times = [e['timestamp'] for e in events if e['name'] == start_event]
    end_times = [e['timestamp'] for e in events if e['name'] == end_event]

    if len(start_times) != len(end_times):
        raise ValueError("Mismatch in number of start/end events")
    
    latencies = [(end - start) * 1000 for start, end in zip(start_times, end_times)]
    return latencies


def compute_jitter(latencies: List[float]) -> float:
    """
    Compute jitter as the standard deviation of latencies.

    Args:
        latencies (List[float]): Latency measurements in ms.

    Returns:
        float: Jitter in ms.
    """
    return float(np.std(latencies))


def generate_plots(latencies: List[float], output_dir: str) -> None:
    """
    Generate latency histogram plot.

    Args:
        latencies (List[float]): Latency measurements.
        output_dir (str): Directory to save plots.
    """
    os.makedirs(output_dir, exist_ok=True)
    plt.figure(figsize=(8, 5))
    plt.hist(latencies, bins=30, color='skyblue', edgecolor='black')
    plt.title("Latency Distribution")
    plt.xlabel("Latency (ms)")
    plt.ylabel("Frequency")
    plt.grid(True)
    plt.tight_layout()
    plot_path = os.path.join(output_dir, "latency_histogram.png")
    plt.savefig(plot_path)
    plt.close()
    print(f"[INFO] Plot saved to {plot_path}")


def save_results(latencies: List[float], output_dir: str) -> None:
    """
    Save latency metrics to a JSON file.

    Args:
        latencies (List[float]): Latency measurements.
        output_dir (str): Directory to save results.
    """
    results = {
        "min_latency_ms": float(np.min(latencies)),
        "max_latency_ms": float(np.max(latencies)),
        "avg_latency_ms": float(np.mean(latencies)),
        "jitter_ms": compute_jitter(latencies),
        "num_samples": len(latencies)
    }
    os.makedirs(output_dir, exist_ok=True)
    result_file = os.path.join(output_dir, "latency_results.json")
    with open(result_file, 'w') as f:
        json.dump(results, f, indent=4)
    print(f"[INFO] Results saved to {result_file}")


def main():
    parser = argparse.ArgumentParser(description="Halo.OS VBS Performance Analyzer")
    parser.add_argument("--input", required=True, help="Input JSONL trace file")
    parser.add_argument("--output", required=True, help="Output directory for results")
    parser.add_argument("--start_event", default="camera_trigger", help="Start event name")
    parser.add_argument("--end_event", default="brake_applied", help="End event name")
    args = parser.parse_args()

    try:
        events = parse_trace(args.input)
        latencies = compute_latency(events, args.start_event, args.end_event)
        generate_plots(latencies, args.output)
        save_results(latencies, args.output)
        print(f"[INFO] Analysis completed successfully. {len(latencies)} samples processed.")
    except Exception as e:
        print(f"[ERROR] {e}")


if __name__ == "__main__":
    main()
