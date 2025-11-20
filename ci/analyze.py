#!/usr/bin/env python3
import pandas as pd
import sys
from pathlib import Path
import json

def load_lttng(dir_path):
    events = []
    for f in Path(dir_path).rglob("*.log"):
        with open(f) as fp:
            for line in fp:
                if "halo_" in line:
                    try:
                        payload = json.loads(line.split(" ", 1)[1])
                        events.append(payload)
                    except:
                        continue
    return pd.DataFrame(events)

if len(sys.argv) < 2:
    print("Usage: python analyze.py <path_to_events.jsonl>")
    sys.exit(1)

trace_dir = sys.argv[1]
df = load_lttng(trace_dir)

# End-to-end latency: camera -> brake
ingest = df[df['name'] == 'halo_camera_ingest'].set_index('frame_id')['time']
actuate = df[df['name'] == 'halo_brake_actuate'].set_index('frame_id')['time']
lat_ms = (actuate - ingest) / 1e6  # convert ns to ms

print(f"Samples: {len(lat_ms)}")
print(f"Mean latency : {lat_ms.mean():.2f} ms")
print(f"p50          : {lat_ms.quantile(0.50):.2f} ms")
print(f"p99.99 jitter: {(lat_ms.quantile(0.9999) - lat_ms.quantile(0.50)):.2f} ms")

# Optional: NPU virtualization overhead analysis
npu_bare_file = Path(trace_dir) / "npu_bare.log"
npu_shared_file = Path(trace_dir) / "npu_shared.log"
if npu_bare_file.exists() and npu_shared_file.exists():
    npu_bare = pd.read_csv(npu_bare_file, delim_whitespace=True)
    npu_shared = pd.read_csv(npu_shared_file, delim_whitespace=True)
    overhead = (npu_bare['GR3D_FREQ'].mean() - npu_shared['GR3D_FREQ'].mean()) / npu_bare['GR3D_FREQ'].mean() * 100
    print(f"NPU virtualization overhead: {overhead:.1f}%")
