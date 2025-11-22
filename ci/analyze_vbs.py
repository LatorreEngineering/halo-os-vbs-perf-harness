#!/usr/bin/env python3
import argparse
import json
import pandas as pd
import numpy as np
from datetime import datetime

def analyze_traces(jsonl_file, output_file):
    try:
        df = pd.read_json(jsonl_file, lines=True)
        if df.empty:
            raise ValueError("No trace events found")
        df['ts'] = pd.to_datetime(df['timestamp'], unit='ns')
        df['task_id'] = df.get('task_id', 0)  # Default if no task_id in traces
        
        # Latency: Match camera_frame to next brake_actuate by time
        camera_events = df[df['event'] == 'camera_frame'].set_index('ts')
        brake_events = df[df['event'] == 'brake_actuate'].set_index('ts')
        latencies = []
        for cam_ts in camera_events.index:
            next_brake = brake_events.index[brake_events.index > cam_ts]
            if not next_brake.empty:
                latencies.append((next_brake[0] - cam_ts).total_seconds() * 1000)  # ms
        latencies = pd.Series(latencies)
        
        # Jitter: p99.99 of latencies
        jitter = latencies.quantile(0.9999) if not latencies.empty else np.nan
        
        # NPU overhead: Pair start/end by task_id and event type
        native_starts = df[(df['event'] == 'npu_native_start')].set_index(['task_id', 'ts'])
        native_ends = df[(df['event'] == 'npu_native_end')].set_index(['task_id', 'ts'])
        virt_starts = df[(df['event'] == 'npu_virt_start')].set_index(['task_id', 'ts'])
        virt_ends = df[(df['event'] == 'npu_virt_end')].set_index(['task_id', 'ts'])
        
        native_deltas = []
        for task_id in native_starts.index.get_level_values(0).unique():
            start = native_starts.loc[task_id].index
            end = native_ends.loc[task_id].index
            if not start.empty and not end.empty:
                native_deltas.append((end[0] - start[0]).total_seconds())
        native_times = pd.Series(native_deltas)
        
        virt_deltas = []  # Similar for virtualized
        for task_id in virt_starts.index.get_level_values(0).unique():
            start = virt_starts.loc[task_id].index
            end = virt_ends.loc[task_id].index
            if not start.empty and not end.empty:
                virt_deltas.append((end[0] - start[0]).total_seconds())
        virt_times = pd.Series(virt_deltas)
        
        overhead = ((virt_times.mean() - native_times.mean()) / native_times.mean() * 100
                    if len(native_times) > 0 and len(virt_times) > 0 else np.nan)
        
        metrics = {
            'latency_p50': latencies.median() if not latencies.empty else np.nan,
            'latency_p99.99': latencies.quantile(0.9999) if not latencies.empty else np.nan,
            'jitter_p99.99': jitter,
            'npu_overhead_pct': overhead,
            'num_events': len(df),
            'run_date': datetime.now().isoformat()
        }
        
        with open(output_file, 'w') as f:
            json.dump(metrics, f, indent=2, default=str)
        
        print(f"Metrics: Latency p50={metrics['latency_p50']:.1f} ms, "
              f"Jitter p99.99={metrics['jitter_p99.99']:.1f} ms, "
              f"Overhead={metrics['npu_overhead_pct']:.1f}% "
              f"(from {metrics['num_events']} events)")
    
    except Exception as e:
        print(f"Analysis failed: {e}")
        metrics = {'error': str(e), 'run_date': datetime.now().isoformat()}
        with open(output_file, 'w') as f:
            json.dump(metrics, f, indent=2)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Analyze VBS traces for perf metrics')
    parser.add_argument('jsonl', help='Input JSONL trace file')
    parser.add_argument('--output', '-o', default='metrics.json', help='Output metrics file')
    args = parser.parse_args()
    analyze_traces(args.jsonl, args.output)
