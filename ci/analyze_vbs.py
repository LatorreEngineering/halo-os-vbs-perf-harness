#!/usr/bin/env python3
import argparse
import json
import pandas as pd
import numpy as np
from datetime import datetime

def analyze_traces(jsonl_file, output_file):
    df = pd.read_json(jsonl_file, lines=True)
    df['ts'] = pd.to_datetime(df['timestamp'], unit='ns')
    
    # Latency: camera → brake
    camera_events = df[df['event'] == 'camera_frame']['ts']
    brake_events = df[df['event'] == 'brake_actuate']['ts']
    latencies = (brake_events - camera_events.shift()).dropna().dt.total_seconds() * 1000  # ms
    
    # Jitter: p99.99
    jitter = latencies.quantile(0.9999)
    
    # NPU overhead: (virtual - native) / native (assume dual runs)
    npu_native = df[df['event'] == 'npu_native_end']['ts'] - df[df['event'] == 'npu_native_start']['ts']
    npu_virt = df[df['event'] == 'npu_virt_end']['ts'] - df[df['event'] == 'npu_virt_start']['ts']
    overhead = ((npu_virt.mean() - npu_native.mean()) / npu_native.mean()) * 100 if len(npu_native) > 0 else 0
    
    metrics = {
        'latency_p50': latencies.median(),
        'latency_p99.99': latencies.quantile(0.9999),
        'jitter_p99.99': jitter,
        'npu_overhead_pct': overhead,
        'run_date': datetime.now().isoformat()
    }
    
    with open(output_file, 'w') as f:
        json.dump(metrics, f, indent=2)
    
    print(f"Metrics: Latency {metrics['latency_p50']:.1f} ms, Jitter {metrics['jitter_p99.99']:.1f} ms, Overhead {metrics['npu_overhead_pct']:.1f}%")

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('jsonl', help='Input JSONL traces')
    parser.add_argument('--output', '-o', default='metrics.json', help='Output file')
    args = parser.parse_args()
    analyze_traces(args.jsonl, args.output)
