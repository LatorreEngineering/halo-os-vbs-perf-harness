# Halo.OS AEB Benchmark Specification

## Vehicle
- Reference vehicle: Li Auto L9
- Test speed: 120 km/h
- Road type: dry asphalt, straight, no slope
- Obstacles: stationary 1 m x 1 m box

## Scenario
- Scenario duration: 30-300 seconds
- Sensor inputs: front camera, LiDAR (optional)
- ROS2 bag used: `examples/aeb_120kph.rosbag`
- NPU utilization: AI perception tasks

## Metrics
- Camera → brake latency (ms)
- 99.99th percentile jitter (ms)
- NPU virtualization overhead (%)
- CPU/NPU utilization (%)

## Edge Cases
- Sensor frame drops
- Network delays (simulated CAN/Ethernet jitter)
- CPU/NPU contention
