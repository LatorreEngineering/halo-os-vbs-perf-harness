#!/usr/bin/env python3
"""
Halo.OS VBS Performance Trace Analyzer
Measures end-to-end latency, jitter, and NPU virtualization overhead.
"""

import argparse
import json
from datetime import datetime
from typing import Optional

import numpy as np
import pandas as pd


def analyze_traces(jsonl_path: str, output_path: str = "metrics.json") -> None:
    """
    Analyze LTTng trace in JSONL format and output performance metrics.
    """
    try:
        df = pd.read_json(jsonl_path, lines=True)

        if df.empty:
            raise ValueError("Trace file is empty or contains no events")

        # Convert timestamp (nanoseconds) to datetime
        df["ts"] = pd.to_datetime(df["timestamp"], unit="ns")

        # ------------------------------------------------------------------
        # 1. End-to-end latency: camera_frame → brake_actuate
        # ------------------------------------------------------------------
        cam_events = df[df["event"] == "camera_frame"]["ts"].values
        brake_events = df[df["event"] == "brake_actuate"]["ts"].values

        latencies_ms = []
        if len(cam_events) > 0 and len(brake_events) > 0:
            j = 0
            for t_cam in cam_events:
                while j < len(brake_events) and brake_events[j] <= t_cam:
                    j += 1
                if j < len(brake_events):
                    delta = (brake_events[j] - t_cam).total_seconds() * 1000
                    latencies_ms.append(delta)

        latency_series = pd.Series(latencies_ms)
        latency_p50 = float(latency_series.median()) if not latency_series.empty else None
        latency_p9999 = float(latency_series.quantile(0.9999)) if not latency_series.empty else None
        jitter_p9999 = (latency_p9999 - latency_p50) if latency_p50 is not None and latency_p9999 is not None else None

        # ------------------------------------------------------------------
        # 2. NPU virtualization overhead
        # ------------------------------------------------------------------
        def get_durations(start_event: str, end_event: str) -> np.ndarray:
            starts = df[df["event"] == start_event]["ts"].values
            ends = df[df["event"] == end_event]["ts"].values
            n = min(len(starts), len(ends))
            if n == 0:
                return np.array([])
            deltas_us = [(ends[i] - starts[i]).total_seconds() * 1e6 for i in range(n)]
            return np.array(deltas_us)

        native_us = get_durations("npu_native_start", "npu_native_end")
        virt_us = get_durations("npu_virt_start", "npu_virt_end")

        overhead_pct: Optional[float] = None
        if len(native_us) > 0 and len(virt_us) > 0:
            overhead_pct = (virt_us.mean() - native_us.mean()) / native_us.mean() * 100

        # ------------------------------------------------------------------
        # Final metrics
        # ------------------------------------------------------------------
        metrics = {
            "latency_p50_ms": latency_p50,
            "latency_p99.99_ms": latency_p9999,
            "jitter_p99.99_ms": jitter_p9999,
            "npu_overhead_pct": overhead_pct,
            "total_events": len(df),
            "analysis_timestamp": datetime.utcnow().isoformat() + "Z",
        }

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(metrics, f, indent=2)

        print("Analysis complete:")
        for key, value in metrics.items():
            print(f"  {key:20}: {value}")

    except Exception as e:
        error_metrics = {
            "error": str(e),
            "analysis_timestamp": datetime.utcnow().isoformat() + "Z",
        }
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(error_metrics, f, indent=2)
        print(f"Analysis failed: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Halo.OS VBS trace analyzer")
    parser.add_argument("jsonl", help="Path to events.jsonl from LTTng")
    parser.add_argument("--output", "-o", default="metrics.json", help="Output metrics file")
    args = parser.parse_args()
    analyze_traces(args.jsonl, args.output)
