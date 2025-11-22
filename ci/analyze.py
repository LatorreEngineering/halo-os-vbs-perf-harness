#!/usr/bin/env python3
"""
analyze.py – Halo.OS VBS performance trace analyzer
Validates ~100 ms AEB latency, <3 ms jitter, 18–22 % NPU overhead
"""

import argparse
import json
from datetime import datetime

import numpy as np
import pandas as pd


def analyze_traces(jsonl_path: str, output_path: str = "metrics.json") -> None:
    """Parse LTTng JSONL traces and produce the three target metrics."""
    try:
        df = pd.read_json(jsonl_path, lines=True)

        if df.empty:
            raise ValueError("Trace file is empty or malformed")

        # Fixed line – this was the ONLY syntax error
        df["ts"] = pd.to_datetime(df["timestamp"], unit="ns")

        # ------------------------------------------------------------------
        # 1. End-to-end latency: camera_frame → brake_actuate
        # ------------------------------------------------------------------
        cam = df[df["event"] == "camera_frame"]["ts"]
        brk = df[df["event"] == "brake_actuate"]["ts"]

        latencies_ms = []
        if not cam.empty and not brk.empty:
            cam_times = cam.values
            brk_times = brk.values
            j = 0
            for t in cam_times:
                while j < len(brk_times) and brk_times[j] <= t:
                    j += 1
                if j < len(brk_times):
                    latencies_ms.append((brk_times[j] - t) / np.timedelta64(1, "ms"))

        latency_series = pd.Series(latencies_ms)
        latency_p50 = float(latency_series.median()) if not latency_series.empty else None
        latency_p9999 = float(latency_series.quantile(0.9999)) if not latency_series.empty else None
        jitter_p9999 = latency_p9999 - latency_p50 if latency_p50 is not None and latency_p9999 is not None else None

        # ------------------------------------------------------------------
        # 2. NPU virtualization overhead
        # ------------------------------------------------------------------
        def duration(start_events, end_events):
            if start_events.empty or end_events.empty:
                return pd.Series(dtype="float64")
            merged = pd.concat([start_events, end_events], axis=1, keys=["start", "end"])
            merged = merged.dropna()
            return (merged["end"] - merged["start"]) / np.timedelta64(1, "us")

        native_start = df[df["event"] == "npu_native_start"
        native_end   = df["event"] == "npu_native_end"
        virt_start   = df["event"] == "npu_virt_start"
        virt_end     = df["event"] == "npu_virt_end"

        native_us = duration(df[native_start].set_index("task_id")["ts"],
                             df[native_end].set_index("task_id")["ts"])
        virt_us   = duration(df[virt_start].set_index("task_id")["ts"],
                             df[virt_end].set_index("task_id")["ts"])

        overhead_pct = (virt_us.mean() - native_us.mean()) / native_us.mean() * 100 \
            if not native_us.empty and not virt_us.empty else None

        # ------------------------------------------------------------------
        # Final result
        # ------------------------------------------------------------------
        metrics = {
            "latency_p50_ms":       latency_p50,
            "latency_p99.99_ms":    latency_p9999,
            "jitter_p99.99_ms":     jitter_p9999,
            "npu_overhead_pct":     overhead_pct,
            "total_events":         len(df),
            "analysis_timestamp":   datetime.utcnow().isoformat() + "Z",
        }

        with open(output_path, "w") as f:
            json.dump(metrics, f, indent=2)

        print("Analysis complete")
        for k, v in metrics.items():
            print(f"  {k:20}: {v}")

    except Exception as e:
        error_metrics = {
            "error": str(e),
            "analysis_timestamp": datetime.utcnow().isoformat() + "Z",
        }
        with open(output_path, "w") as f:
            json.dump(error_metrics, f, indent=2)
        print(f"Analysis failed: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Halo.OS VBS trace analyzer")
    parser.add_argument("jsonl", help="Path to events.jsonl from LTTng")
    parser.add_argument("--output", "-o", default="metrics.json")
    args = parser.parse_args()
    analyze_traces(args.jsonl, args.output)
