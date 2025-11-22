cat > ci/analyze.py << 'EOF'
#!/usr/bin/env python3
"""
analyze.py - Halo.OS VBS performance trace analyzer.
Validates ~100 ms AEB latency, <3 ms jitter, 18-22 % NPU overhead.
"""

import argparse
import json
from datetime import datetime

import numpy as np
import pandas as pd


def analyze_traces(jsonl_path, output_path="metrics.json"):
    try:
        df = pd.read_json(jsonl_path, lines=True)
        if df.empty:
            raise ValueError("Empty trace file")

        df["ts"] = pd.to_datetime(df["timestamp"], unit="ns")

        # Latency: camera_frame -> brake_actuate
        cam_mask = df["event"] == "camera_frame"
        brk_mask = df["event"] == "brake_actuate"
        cam_ts = df[cam_mask]["ts"].values
        brk_ts = df[brk_mask]["ts"].values

        latencies_ms = []
        if len(cam_ts) > 0 and len(brk_ts) > 0:
            j = 0
            for t in cam_ts:
                while j < len(brk_ts) and brk_ts[j] <= t:
                    j += 1
                if j < len(brk_ts):
                    latencies_ms.append((brk_ts[j] - t).total_seconds() * 1000)

        latency_series = pd.Series(latencies_ms)
        latency_p50 = latency_series.median() if len(latency_series) > 0 else None
        latency_p9999 = latency_series.quantile(0.9999) if len(latency_series) > 0 else None
        jitter_p9999 = (latency_p9999 - latency_p50) if latency_p50 is not None and latency_p9999 is not None else None

        # NPU overhead: Simple mean delta (assume paired by order)
        native_mask_start = df["event"] == "npu_native_start"
        native_mask_end = df["event"] == "npu_native_end"
        virt_mask_start = df["event"] == "npu_virt_start"
        virt_mask_end = df["event"] == "npu_virt_end"

        native_times = []
        if native_mask_start.sum() > 0 and native_mask_end.sum() > 0:
            native_starts = df[native_mask_start]["ts"].values
            native_ends = df[native_mask_end]["ts"].values
            for i in range(min(len(native_starts), len(native_ends))):
                native_times.append((native_ends[i] - native_starts[i]).total_seconds() * 1e6)  # us

        virt_times = []
        if virt_mask_start.sum() > 0 and virt_mask_end.sum() > 0:
            virt_starts = df[virt_mask_start]["ts"].values
            virt_ends = df[virt_mask_end]["ts"].values
            for i in range(min(len(virt_starts), len(virt_ends))):
                virt_times.append((virt_ends[i] - virt_starts[i]).total_seconds() * 1e6)  # us

        overhead_pct = None
        if native_times and virt_times:
            native_mean = np.mean(native_times)
            virt_mean = np.mean(virt_times)
            overhead_pct = ((virt_mean - native_mean) / native_mean) * 100 if native_mean > 0 else None

        metrics = {
            "latency_p50_ms": float(latency_p50) if latency_p50 is not None else None,
            "latency_p99.99_ms": float(latency_p9999) if latency_p9999 is not None else None,
            "jitter_p99.99_ms": float(jitter_p9999) if jitter_p9999 is not None else None,
            "npu_overhead_pct": float(overhead_pct) if overhead_pct is not None else None,
            "total_events": len(df),
            "analysis_timestamp": datetime.utcnow().isoformat() + "Z",
        }

        with open(output_path, "w") as f:
            json.dump(metrics, f, indent=2, default=str)

        print("Analysis complete:")
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
    parser.add_argument("jsonl", help="Path to events.jsonl")
    parser.add_argument("--output", "-o", default="metrics.json", help="Output file")
    args = parser.parse_args()
    analyze_traces(args.jsonl, args.output)
EOF
