#!/usr/bin/env python3
import pandas as pd
import sys
from pathlib import Path

def load_lttng(dir_path):
    events = []
    for f in Path(dir_path).rglob("*.log"):
        for line in open(f):
            if "halo_" in line:
                payload = eval(line.split(" ", 1)[1])  # JSON or Python dict
                events.append(payload)
    return pd.DataFrame(events)

trace_dir = sys.argv[1]
df = load_lttng(trace_dir)

# Latency: camera → brake
ingest = df[df['name'] == 'halo_camera_ingest'].set_index('frame_id')['time']
actuate = df[df['name'] == 'halo_brake_actuate'].set_index('frame_id')['time']
lat_ms = (actuate - ingest) / 1e6

print(f"Samples: {len(lat_ms)}")
print(f"Mean latency : {lat_ms.mean():.2f} ms")
print(f"p50          : {lat_ms.quantile(0.50):.2f} ms")
print(f"p99.99 jitter: {(lat_ms.quantile(0.9999) - lat_ms.quantile(0.50)):.2f} ms")

# NPU/GPU overhead (if logs exist)
npu_file = Path(trace_dir) / "tegrastats.log"
if npu_file.exists():
    npu = pd.read_csv(npu_file, delim_whitespace=True, comment="#", header=None, names=["time","cpu","gpu","gr3d"])
    overhead = 100 - (npu['gr3d'].mean() / npu['gr3d'].max() * 100)
    print(f"NPU/GPU utilization overhead: {overhead:.2f}%")
