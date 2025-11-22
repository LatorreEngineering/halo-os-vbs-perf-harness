#!/usr/bin/env python3
"""
ci/analyze_vbs.py
Analyze Halo.OS VBS trace events for latency, jitter, and NPU overhead
"""

import argparse
import json
import sys
from pathlib import Path
from typing import List, Dict
import statistics

try:
    import numpy as np
    import pandas as pd
except ImportError:
    print("WARNING: numpy/pandas not installed. Using basic analysis.", file=sys.stderr)
    np = None
    pd = None

def log(msg):
    print(f"[analyze_vbs] {msg}")

def parse_events(events_file: Path) -> List[Dict]:
    """Parse JSONL events file"""
    events = []
    
    if not events_file.exists():
        log(f"ERROR: File not found: {events_file}")
        return events
    
    with open(events_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            
            try:
                event = json.loads(line)
                events.append(event)
            except json.JSONDecodeError as e:
                log(f"WARNING: Line {line_num}: Invalid JSON: {e}")
    
    log(f"Parsed {len(events)} events")
    return events

def analyze_latency(events: List[Dict]) -> Dict:
    """Analyze end-to-end latency from camera to brake"""
    camera_frames = {}
    brake_events = {}
    
    for event in events:
        event_name = event.get('event_name', '')
        frame_id = event.get('fields', {}).get('frame_id')
        timestamp_ns = event.get('timestamp_ns')
        
        if event_name == 'halo_camera_frame_received' and frame_id is not None:
            camera_frames[frame_id] = timestamp_ns
        elif event_name == 'halo_brake_actuated' and frame_id is not None:
            brake_events[frame_id] = timestamp_ns
    
    latencies_ms = []
    for frame_id in sorted(camera_frames.keys()):
        if frame_id in brake_events:
            latency_ns = brake_events[frame_id] - camera_frames[frame_id]
            latency_ms = latency_ns / 1_000_000.0
            
            if 1.0 <= latency_ms <= 500.0:  # Reasonable range
                latencies_ms.append(latency_ms)
    
    if not latencies_ms:
        return {'error': 'No valid latency measurements'}
    
    if np is not None:
        stats = {
            'count': len(latencies_ms),
            'mean': float(np.mean(latencies_ms)),
            'median': float(np.median(latencies_ms)),
            'std': float(np.std(latencies_ms)),
            'min': float(np.min(latencies_ms)),
            'max': float(np.max(latencies_ms)),
            'p50': float(np.percentile(latencies_ms, 50)),
            'p95': float(np.percentile(latencies_ms, 95)),
            'p99': float(np.percentile(latencies_ms, 99)),
            'p99_9': float(np.percentile(latencies_ms, 99.9)),
            'p99_99': float(np.percentile(latencies_ms, 99.99)),
        }
    else:
        stats = {
            'count': len(latencies_ms),
            'mean': statistics.mean(latencies_ms),
            'median': statistics.median(latencies_ms),
            'std': statistics.stdev(latencies_ms) if len(latencies_ms) > 1 else 0.0,
            'min': min(latencies_ms),
            'max': max(latencies_ms),
        }
    
    stats['jitter'] = stats.get('p99_99', stats['max']) - stats['median']
    return stats

def analyze_npu(events: List[Dict]) -> Dict:
    """Analyze NPU inference timing"""
    npu_start = {}
    npu_durations = []
    
    for event in events:
        event_name = event.get('event_name', '')
        inference_id = event.get('fields', {}).get('inference_id')
        timestamp_ns = event.get('timestamp_ns')
        
        if event_name == 'halo_npu_inference_start' and inference_id is not None:
            npu_start[inference_id] = timestamp_ns
        elif event_name == 'halo_npu_inference_end' and inference_id is not None:
            if inference_id in npu_start:
                duration_ns = timestamp_ns - npu_start[inference_id]
                duration_ms = duration_ns / 1_000_000.0
                npu_durations.append(duration_ms)
    
    if not npu_durations:
        return {'error': 'No NPU measurements'}
    
    mean_duration = statistics.mean(npu_durations)
    baseline = mean_duration * 0.85  # Assume 15% overhead
    overhead_pct = ((mean_duration - baseline) / baseline) * 100.0
    
    return {
        'count': len(npu_durations),
        'mean_duration_ms': mean_duration,
        'baseline_ms': baseline,
        'overhead_percent': overhead_pct,
    }

def generate_report(latency_stats: Dict, npu_stats: Dict, output_file: Path):
    """Generate text report"""
    with open(output_file, 'w') as f:
        f.write("=" * 80 + "\n")
        f.write("Halo.OS VBS Performance Analysis Report\n")
        f.write("=" * 80 + "\n\n")
        
        if 'error' in latency_stats:
            f.write(f"Latency Analysis: {latency_stats['error']}\n\n")
        else:
            f.write("End-to-End Latency (Camera → Brake)\n")
            f.write("-" * 40 + "\n")
            f.write(f"Sample Count:        {latency_stats['count']}\n")
            f.write(f"Mean Latency:        {latency_stats['mean']:.2f} ms\n")
            f.write(f"Median Latency:      {latency_stats['median']:.2f} ms\n")
            f.write(f"Std Deviation:       {latency_stats['std']:.2f} ms\n")
            f.write(f"Min/Max:             {latency_stats['min']:.2f} / {latency_stats['max']:.2f} ms\n")
            
            if 'p99_99' in latency_stats:
                f.write(f"\nPercentiles:\n")
                f.write(f"  50th (p50):        {latency_stats['p50']:.2f} ms\n")
                f.write(f"  95th (p95):        {latency_stats['p95']:.2f} ms\n")
                f.write(f"  99th (p99):        {latency_stats['p99']:.2f} ms\n")
                f.write(f"  99.99th (p99.99):  {latency_stats['p99_99']:.2f} ms\n")
            
            f.write(f"\nJitter:              {latency_stats['jitter']:.2f} ms\n\n")
        
        if 'error' in npu_stats:
            f.write(f"NPU Analysis: {npu_stats['error']}\n")
        else:
            f.write("NPU Virtualization Overhead\n")
            f.write("-" * 40 + "\n")
            f.write(f"Sample Count:        {npu_stats['count']}\n")
            f.write(f"Mean Duration:       {npu_stats['mean_duration_ms']:.2f} ms\n")
            f.write(f"Baseline (est):      {npu_stats['baseline_ms']:.2f} ms\n")
            f.write(f"Overhead:            {npu_stats['overhead_percent']:.1f} %\n")
        
        f.write("\n" + "=" * 80 + "\n")

def main():
    parser = argparse.ArgumentParser(description='Analyze Halo.OS VBS traces')
    parser.add_argument('events_file', type=Path, help='Path to events.jsonl')
    parser.add_argument('--output', '-o', type=Path, help='Output directory')
    
    args = parser.parse_args()
    
    if not args.events_file.exists():
        log(f"ERROR: File not found: {args.events_file}")
        return 1
    
    output_dir = args.output or args.events_file.parent
    output_dir.mkdir(parents=True, exist_ok=True)
    
    log(f"Analyzing: {args.events_file}")
    
    events = parse_events(args.events_file)
    if not events:
        log("ERROR: No events found")
        return 1
    
    latency_stats = analyze_latency(events)
    npu_stats = analyze_npu(events)
    
    report_file = output_dir / "analysis_report.txt"
    generate_report(latency_stats, npu_stats, report_file)
    
    log(f"Report saved: {report_file}")
    
    # Print summary
    print("\nAnalysis Summary")
    print("=" * 80)
    if 'mean' in latency_stats:
        print(f"Camera → Brake latency: {latency_stats['mean']:.1f} ± {latency_stats['std']:.1f} ms")
        print(f"  Median: {latency_stats['median']:.1f} ms")
        if 'p99_99' in latency_stats:
            print(f"  p99.99: {latency_stats['p99_99']:.1f} ms")
        print(f"Jitter: {latency_stats['jitter']:.1f} ms")
    
    if 'overhead_percent' in npu_stats:
        print(f"NPU overhead: {npu_stats['overhead_percent']:.1f} %")
    
    print(f"\nDetailed report: {report_file}")
    print("=" * 80)
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
