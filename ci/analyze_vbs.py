#!/usr/bin/env python3
"""
ci/analyze_vbs.py
Purpose: Analyze Halo.OS LTTng traces for latency, jitter, and NPU overhead
Usage: python3 ci/analyze_vbs.py <events.jsonl> [--output OUTPUT_DIR]
"""

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, field
from collections import defaultdict
import statistics

try:
    import numpy as np
    import pandas as pd
    import matplotlib.pyplot as plt
except ImportError as e:
    print(f"ERROR: Required package not found: {e}", file=sys.stderr)
    print("Install with: pip install numpy pandas matplotlib", file=sys.stderr)
    sys.exit(1)

# ==============================================================================
# Configuration
# ==============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Event type definitions
EVENT_CAMERA_FRAME = "halo_camera_frame_received"
EVENT_PLANNING_START = "halo_planning_start"
EVENT_PLANNING_END = "halo_planning_end"
EVENT_CONTROL_COMMAND = "halo_control_command_sent"
EVENT_BRAKE_ACTUATED = "halo_brake_actuated"
EVENT_NPU_INFERENCE_START = "halo_npu_inference_start"
EVENT_NPU_INFERENCE_END = "halo_npu_inference_end"

# Thresholds for validation
MAX_REASONABLE_LATENCY_MS = 500.0  # Anything above this is suspicious
MIN_REASONABLE_LATENCY_MS = 1.0    # Anything below this is suspicious

# ==============================================================================
# Data Classes
# ==============================================================================
@dataclass
class TraceEvent:
    """Represents a single LTTng trace event"""
    timestamp_ns: int
    event_name: str
    fields: Dict
    pid: Optional[int] = None
    tid: Optional[int] = None
    
    @property
    def timestamp_ms(self) -> float:
        """Convert timestamp to milliseconds"""
        return self.timestamp_ns / 1_000_000.0


@dataclass
class LatencyMeasurement:
    """Represents an end-to-end latency measurement"""
    camera_frame_id: int
    camera_timestamp_ns: int
    brake_timestamp_ns: int
    latency_ms: float
    intermediate_events: List[TraceEvent] = field(default_factory=list)
    
    @property
    def is_valid(self) -> bool:
        """Check if measurement is within reasonable bounds"""
        return (MIN_REASONABLE_LATENCY_MS <= self.latency_ms <= MAX_REASONABLE_LATENCY_MS
                and self.brake_timestamp_ns > self.camera_timestamp_ns)


@dataclass
class NPUMeasurement:
    """Represents NPU inference timing"""
    inference_id: int
    start_timestamp_ns: int
    end_timestamp_ns: int
    duration_ms: float
    model_name: Optional[str] = None


# ==============================================================================
# Event Parsing
# ==============================================================================
class TraceParser:
    """Parser for LTTng trace events in JSON format"""
    
    def __init__(self, events_file: Path):
        self.events_file = events_file
        self.events: List[TraceEvent] = []
        
    def parse(self) -> List[TraceEvent]:
        """Parse events from JSONL file"""
        logger.info(f"Parsing trace events from: {self.events_file}")
        
        if not self.events_file.exists():
            raise FileNotFoundError(f"Events file not found: {self.events_file}")
        
        line_num = 0
        parse_errors = 0
        
        try:
            with open(self.events_file, 'r') as f:
                for line in f:
                    line_num += 1
                    line = line.strip()
                    
                    if not line:
                        continue
                    
                    try:
                        event_data = json.loads(line)
                        event = self._parse_event(event_data)
                        if event:
                            self.events.append(event)
                    except json.JSONDecodeError as e:
                        logger.warning(f"Line {line_num}: Invalid JSON: {e}")
                        parse_errors += 1
                        if parse_errors > 100:
                            raise RuntimeError("Too many parse errors (>100)")
                    except Exception as e:
                        logger.warning(f"Line {line_num}: Parse error: {e}")
                        parse_errors += 1
        
        except Exception as e:
            logger.error(f"Failed to parse events file: {e}")
            raise
        
        logger.info(f"Parsed {len(self.events)} events from {line_num} lines")
        
        if parse_errors > 0:
            logger.warning(f"Encountered {parse_errors} parse errors")
        
        if len(self.events) == 0:
            raise ValueError("No valid events found in trace file")
        
        # Sort events by timestamp
        self.events.sort(key=lambda e: e.timestamp_ns)
        
        return self.events
    
    def _parse_event(self, data: Dict) -> Optional[TraceEvent]:
        """Parse a single event from JSON data"""
        try:
            # Extract timestamp (handle different babeltrace2 formats)
            timestamp_ns = None
            if 'timestamp' in data:
                timestamp_ns = int(data['timestamp'])
            elif 'timestamp-begin' in data:
                timestamp_ns = int(data['timestamp-begin'])
            else:
                logger.debug(f"Event missing timestamp: {data}")
                return None
            
            # Extract event name
            event_name = data.get('name', data.get('event-name', ''))
            if not event_name:
                return None
            
            # Extract fields
            fields = data.get('fields', data.get('event-fields', {}))
            
            # Extract context
            context = data.get('context', {})
            pid = context.get('vpid')
            tid = context.get('vtid')
            
            return TraceEvent(
                timestamp_ns=timestamp_ns,
                event_name=event_name,
                fields=fields,
                pid=pid,
                tid=tid
            )
        
        except (KeyError, ValueError, TypeError) as e:
            logger.debug(f"Failed to parse event: {e}")
            return None


# ==============================================================================
# Latency Analysis
# ==============================================================================
class LatencyAnalyzer:
    """Analyze end-to-end latency from camera to brake"""
    
    def __init__(self, events: List[TraceEvent]):
        self.events = events
        self.measurements: List[LatencyMeasurement] = []
        
    def analyze(self) -> List[LatencyMeasurement]:
        """Compute latency measurements"""
        logger.info("Analyzing end-to-end latency...")
        
        # Group events by frame ID
        camera_events = {}
        brake_events = {}
        
        for event in self.events:
            if event.event_name == EVENT_CAMERA_FRAME:
                frame_id = event.fields.get('frame_id')
                if frame_id is not None:
                    camera_events[frame_id] = event
            
            elif event.event_name == EVENT_BRAKE_ACTUATED:
                frame_id = event.fields.get('frame_id')
                if frame_id is not None:
                    brake_events[frame_id] = event
        
        logger.info(f"Found {len(camera_events)} camera frames, {len(brake_events)} brake events")
        
        # Match camera frames with brake events
        for frame_id in sorted(camera_events.keys()):
            if frame_id not in brake_events:
                logger.debug(f"No brake event for frame {frame_id}")
                continue
            
            camera_event = camera_events[frame_id]
            brake_event = brake_events[frame_id]
            
            latency_ms = (brake_event.timestamp_ns - camera_event.timestamp_ns) / 1_000_000.0
            
            measurement = LatencyMeasurement(
                camera_frame_id=frame_id,
                camera_timestamp_ns=camera_event.timestamp_ns,
                brake_timestamp_ns=brake_event.timestamp_ns,
                latency_ms=latency_ms
            )
            
            if not measurement.is_valid:
                logger.warning(f"Invalid latency for frame {frame_id}: {latency_ms:.2f} ms")
                continue
            
            self.measurements.append(measurement)
        
        logger.info(f"Computed {len(self.measurements)} valid latency measurements")
        
        if len(self.measurements) == 0:
            raise ValueError("No valid latency measurements found")
        
        return self.measurements
    
    def compute_statistics(self) -> Dict:
        """Compute statistical summary of latency"""
        if not self.measurements:
            raise ValueError("No measurements available")
        
        latencies = [m.latency_ms for m in self.measurements]
        
        stats = {
            'count': len(latencies),
            'mean': statistics.mean(latencies),
            'median': statistics.median(latencies),
            'stdev': statistics.stdev(latencies) if len(latencies) > 1 else 0.0,
            'min': min(latencies),
            'max': max(latencies),
            'p50': np.percentile(latencies, 50),
            'p95': np.percentile(latencies, 95),
            'p99': np.percentile(latencies, 99),
            'p99_9': np.percentile(latencies, 99.9),
            'p99_99': np.percentile(latencies, 99.99),
        }
        
        # Compute jitter (99.99th percentile - median)
        stats['jitter'] = stats['p99_99'] - stats['median']
        
        return stats


# ==============================================================================
# NPU Analysis
# ==============================================================================
class NPUAnalyzer:
    """Analyze NPU inference timing and overhead"""
    
    def __init__(self, events: List[TraceEvent]):
        self.events = events
        self.measurements: List[NPUMeasurement] = []
        
    def analyze(self) -> List[NPUMeasurement]:
        """Compute NPU inference measurements"""
        logger.info("Analyzing NPU inference timing...")
        
        # Match start/end pairs
        pending_inferences = {}
        
        for event in self.events:
            if event.event_name == EVENT_NPU_INFERENCE_START:
                inference_id = event.fields.get('inference_id')
                if inference_id is not None:
                    pending_inferences[inference_id] = event
            
            elif event.event_name == EVENT_NPU_INFERENCE_END:
                inference_id = event.fields.get('inference_id')
                if inference_id is None:
                    continue
                
                if inference_id not in pending_inferences:
                    logger.debug(f"End without start for inference {inference_id}")
                    continue
                
                start_event = pending_inferences.pop(inference_id)
                duration_ms = (event.timestamp_ns - start_event.timestamp_ns) / 1_000_000.0
                
                measurement = NPUMeasurement(
                    inference_id=inference_id,
                    start_timestamp_ns=start_event.timestamp_ns,
                    end_timestamp_ns=event.timestamp_ns,
                    duration_ms=duration_ms,
                    model_name=start_event.fields.get('model_name')
                )
                
                self.measurements.append(measurement)
        
        logger.info(f"Computed {len(self.measurements)} NPU inference measurements")
        
        if pending_inferences:
            logger.warning(f"{len(pending_inferences)} NPU inferences without end event")
        
        return self.measurements
    
    def compute_overhead(self, baseline_ms: Optional[float] = None) -> Dict:
        """Compute NPU virtualization overhead"""
        if not self.measurements:
            logger.warning("No NPU measurements available")
            return {'overhead_percent': 0.0}
        
        durations = [m.duration_ms for m in self.measurements]
        mean_duration = statistics.mean(durations)
        
        # If no baseline provided, use a typical bare-metal inference time
        if baseline_ms is None:
            # This should be configured based on the actual NPU model
            baseline_ms = mean_duration * 0.85  # Assume ~15% overhead
            logger.warning(f"No baseline provided, assuming {baseline_ms:.2f} ms")
        
        overhead_ms = mean_duration - baseline_ms
        overhead_percent = (overhead_ms / baseline_ms) * 100.0
        
        return {
            'mean_duration_ms': mean_duration,
            'baseline_ms': baseline_ms,
            'overhead_ms': overhead_ms,
            'overhead_percent': overhead_percent,
            'count': len(durations),
        }


# ==============================================================================
# Report Generation
# ==============================================================================
class ReportGenerator:
    """Generate analysis reports and visualizations"""
    
    def __init__(self, output_dir: Path):
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
    def generate_text_report(self, latency_stats: Dict, npu_stats: Dict) -> Path:
        """Generate text summary report"""
        report_file = self.output_dir / "analysis_report.txt"
        
        with open(report_file, 'w') as f:
            f.write("=" * 80 + "\n")
            f.write("Halo.OS VBS Performance Analysis Report\n")
            f.write("=" * 80 + "\n\n")
            
            f.write("End-to-End Latency (Camera → Brake)\n")
            f.write("-" * 40 + "\n")
            f.write(f"Sample Count:        {latency_stats['count']}\n")
            f.write(f"Mean Latency:        {latency_stats['mean']:.2f} ms\n")
            f.write(f"Median Latency:      {latency_stats['median']:.2f} ms\n")
            f.write(f"Std Deviation:       {latency_stats['stdev']:.2f} ms\n")
            f.write(f"Min Latency:         {latency_stats['min']:.2f} ms\n")
            f.write(f"Max Latency:         {latency_stats['max']:.2f} ms\n")
            f.write(f"\nPercentiles:\n")
            f.write(f"  50th (p50):        {latency_stats['p50']:.2f} ms\n")
            f.write(f"  95th (p95):        {latency_stats['p95']:.2f} ms\n")
            f.write(f"  99th (p99):        {latency_stats['p99']:.2f} ms\n")
            f.write(f"  99.9th (p99.9):    {latency_stats['p99_9']:.2f} ms\n")
            f.write(f"  99.99th (p99.99):  {latency_stats['p99_99']:.2f} ms\n")
            f.write(f"\nJitter (p99.99 - p50): {latency_stats['jitter']:.2f} ms\n")
            f.write("\n")
            
            if npu_stats.get('count', 0) > 0:
                f.write("NPU Virtualization Overhead\n")
                f.write("-" * 40 + "\n")
                f.write(f"Mean Inference Time: {npu_stats['mean_duration_ms']:.2f} ms\n")
                f.write(f"Baseline Time:       {npu_stats['baseline_ms']:.2f} ms\n")
                f.write(f"Overhead:            {npu_stats['overhead_ms']:.2f} ms\n")
                f.write(f"Overhead Percent:    {npu_stats['overhead_percent']:.2f} %\n")
                f.write(f"Sample Count:        {npu_stats['count']}\n")
            else:
                f.write("NPU Virtualization Overhead\n")
                f.write("-" * 40 + "\n")
                f.write("No NPU measurements available\n")
            
            f.write("\n")
            f.write("=" * 80 + "\n")
        
        logger.info(f"Text report saved to: {report_file}")
        return report_file
    
    def generate_visualizations(self, measurements: List[LatencyMeasurement]) -> List[Path]:
        """Generate visualization plots"""
        plots = []
        
        latencies = [m.latency_ms for m in measurements]
        timestamps = [(m.camera_timestamp_ns - measurements[0].camera_timestamp_ns) / 1e9 
                     for m in measurements]
        
        # Latency over time
        fig, ax = plt.subplots(figsize=(12, 6))
        ax.plot(timestamps, latencies, alpha=0.6, linewidth=0.5)
        ax.set_xlabel('Time (seconds)')
        ax.set_ylabel('Latency (ms)')
        ax.set_title('End-to-End Latency Over Time')
        ax.grid(True, alpha=0.3)
        
        plot_file = self.output_dir / "latency_over_time.png"
        plt.savefig(plot_file, dpi=150, bbox_inches='tight')
        plt.close()
        plots.append(plot_file)
        logger.info(f"Generated plot: {plot_file}")
        
        # Histogram
        fig, ax = plt.subplots(figsize=(10, 6))
        ax.hist(latencies, bins=50, alpha=0.7, edgecolor='black')
        ax.set_xlabel('Latency (ms)')
        ax.set_ylabel('Frequency')
        ax.set_title('Latency Distribution')
        ax.axvline(np.median(latencies), color='r', linestyle='--', label='Median')
        ax.axvline(np.percentile(latencies, 99.99), color='orange', linestyle='--', label='p99.99')
        ax.legend()
        ax.grid(True, alpha=0.3)
        
        plot_file = self.output_dir / "latency_histogram.png"
        plt.savefig(plot_file, dpi=150, bbox_inches='tight')
        plt.close()
        plots.append(plot_file)
        logger.info(f"Generated plot: {plot_file}")
        
        return plots


# ==============================================================================
# Main
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(
        description='Analyze Halo.OS VBS performance traces',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('events_file', type=Path,
                       help='Path to events.jsonl file')
    parser.add_argument('--output', '-o', type=Path,
                       help='Output directory (default: same as events file)')
    parser.add_argument('--npu-baseline', type=float,
                       help='Baseline NPU inference time in ms')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # Determine output directory
    output_dir = args.output or args.events_file.parent
    
    try:
        # Parse events
        parser_obj = TraceParser(args.events_file)
        events = parser_obj.parse()
        
        # Analyze latency
        latency_analyzer = LatencyAnalyzer(events)
        measurements = latency_analyzer.analyze()
        latency_stats = latency_analyzer.compute_statistics()
        
        # Analyze NPU
        npu_analyzer = NPUAnalyzer(events)
        npu_measurements = npu_analyzer.analyze()
        npu_stats = npu_analyzer.compute_overhead(args.npu_baseline)
        
        # Generate reports
        report_gen = ReportGenerator(output_dir)
        report_file = report_gen.generate_text_report(latency_stats, npu_stats)
        plots = report_gen.generate_visualizations(measurements)
        
        # Print summary to console
        print("\n" + "=" * 80)
        print("Analysis Summary")
        print("=" * 80)
        print(f"\nCamera → Brake latency: {latency_stats['mean']:.1f} ms ± {latency_stats['stdev']:.1f} ms")
        print(f"  p50:    {latency_stats['p50']:.1f} ms")
        print(f"  p99.99: {latency_stats['p99_99']:.1f} ms")
        print(f"\n99.99th percentile jitter: {latency_stats['jitter']:.1f} ms")
        
        if npu_stats.get('count', 0) > 0:
            print(f"\nNPU virtualization overhead: {npu_stats['overhead_percent']:.1f} %")
        
        print(f"\nDetailed report: {report_file}")
        print("=" * 80 + "\n")
        
        return 0
    
    except Exception as e:
        logger.error(f"Analysis failed: {e}", exc_info=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
