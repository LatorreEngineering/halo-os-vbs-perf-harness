# Halo.OS VBS Performance Harness

[![CI Status](https://github.com/LatorreEngineering/halo-os-vbs-perf-harness/actions/workflows/ci.yml/badge.svg)](https://github.com/LatorreEngineering/halo-os-vbs-perf-harness/actions)

## Goal

Provide a fully open-source, reproducible framework to measure end-to-end latency, jitter, and NPU virtualization overhead of Halo.OS (or any centralized vehicle OS).

This enables independent verification (or refutation) of published numbers:
- **~100 ms AEB latency** (camera → brake)
- **<3 ms jitter** (99.99th percentile)
- **18-22% NPU virtualization overhead**

## Current Status

✅ **Framework Complete**: Analysis pipeline, CI automation, Docker support  
✅ **CI Passing**: Demonstrates framework with realistic mock data  
⚠️ **Waiting for Halo.OS Sources**: Gitee repos currently inaccessible  

### Mock Build (Current)

Since the Halo.OS source repositories at Gitee are currently inaccessible (network restrictions or authentication issues), the CI uses **mock data** to demonstrate the framework:

- **Mock VBSPro build** (`ci/build_mock.sh`): Creates placeholder artifacts
- **Realistic trace generation** (`ci/generate_traces.sh`): Simulates AEB scenario
- **Real analysis** (`ci/analyze_vbs.py`): Processes traces, computes metrics

This proves the framework works end-to-end. When Halo.OS sources become accessible, simply replace the mock scripts with the real build.

## Quick Start

### Option 1: Run CI Demo (Recommended)

```bash
# Clone repository
git clone https://github.com/LatorreEngineering/halo-os-vbs-perf-harness.git
cd halo-os-vbs-perf-harness

# Run mock build
./ci/build_mock.sh

# Generate realistic traces
./ci/generate_traces.sh results/demo

# Analyze traces
python3 ci/analyze_vbs.py results/demo/events.jsonl
```

**Expected Output:**
```
📊 End-to-End Latency (Camera → Brake):
   Mean:    102.4 ms ± 2.1 ms
   Median:  102.0 ms
   p99.99:  108.5 ms

⏱️  Jitter (p99.99 - p50): 2.8 ms

🖥️  NPU Virtualization Overhead: 20.1 %

📈 Comparison with Li Auto Published Metrics:
   Latency: 102.4 ms (target: ~100 ms) ✅
   Jitter:  2.8 ms (target: <3 ms) ✅
   NPU OH:  20.1 % (target: 18-22%) ✅
```

### Option 2: Build Real Halo.OS (When Available)

```bash
# Install dependencies
./ci/setup_env.sh

# Build real VBSPro from Gitee
# NOTE: Requires Gitee access (may need VPN or credentials)
export GITEE_TOKEN=your_token_here  # Optional
./ci/build_halo.sh

# Run experiments on hardware
./ci/run_experiment.sh run001 300
```

## Repository Structure

```
halo-os-vbs-perf-harness/
├── .github/workflows/ci.yml     # CI pipeline (working with mock data)
├── ci/
│   ├── build_mock.sh            # Mock build for CI demo
│   ├── generate_traces.sh       # Generate realistic trace data
│   ├── analyze_vbs.py           # Performance analysis (real code)
│   ├── build_halo.sh            # Real VBSPro build (for when sources available)
│   └── setup_env.sh             # Environment setup
├── build/                       # Build artifacts (generated)
├── results/                     # Trace data and analysis results
├── requirements.txt             # Python dependencies
├── Dockerfile                   # Container environment
└── README.md                    # This file
```

## CI Pipeline

The GitHub Actions CI demonstrates the full workflow:

1. **Validate**: Check all scripts for syntax errors
2. **Build Mock**: Create placeholder VBSPro artifacts
3. **Generate Traces**: Simulate AEB scenario with realistic data
4. **Analyze**: Compute latency, jitter, NPU overhead
5. **Report**: Compare with published metrics

**Status**: ✅ All stages passing

## Switching to Real Halo.OS Build

When Halo.OS sources become accessible:

1. **Update CI workflow** (`.github/workflows/ci.yml`):
   ```yaml
   # Change this:
   - run: ./ci/build_mock.sh
   
   # To this:
   - run: ./ci/build_halo.sh
   ```

2. **Configure Gitee access** (if needed):
   ```bash
   # Add GitHub secret: GITEE_TOKEN
   # Or: GITEE_SSH_KEY for SSH access
   ```

3. **Test locally**:
   ```bash
   # Verify Gitee connectivity
   curl -I https://gitee.com/haloos/manifests.git
   
   # Try manual repo init
   repo init -u https://gitee.com/haloos/manifests.git -m vbs.xml
   repo sync
   ```

## Supported Platforms

- **x86_64 Ubuntu 22.04**: CI, Docker, simulation
- **NVIDIA Jetson Orin**: Target hardware (cross-compile)
- **SemiDrive E3650**: Target hardware (cross-compile)

## Analysis Metrics

The framework measures:

### 1. End-to-End Latency
Camera frame received → Brake actuated

**Metrics**: mean, median, std, p50, p95, p99, p99.99

### 2. Jitter
Variance in end-to-end latency (p99.99 - p50)

**Target**: <3 ms (ISO 26262 Class D)

### 3. NPU Virtualization Overhead
(Virtualized inference time - Native time) / Native time × 100%

**Target**: 18-22% (Li Auto whitepaper)

## Contributing

We welcome:
- Hardware experiment results (Jetson, SemiDrive)
- Additional scenarios (LKA, parking, etc.)
- Analysis improvements
- Documentation updates

**All reproducible results, pass or fail, are valuable.**

## References

- [Li Auto Halo.OS Whitepaper (March 2025)](https://www.lixiang.com/en/news/halo-os)
- [Eclipse SDV Performance Guidelines](https://sdv.eclipse.org/)
- [ISO 26262-8:2018, Clause 11 – Timing Analysis](https://www.iso.org/standard/68388.html)

## License

Apache 2.0 - See [LICENSE](LICENSE) for details.

## FAQ

**Q: Why mock data?**  
A: Gitee repos are currently inaccessible from GitHub Actions. Mock data proves the framework works; real build is ready when sources are available.

**Q: How accurate is the mock data?**  
A: Based on Li Auto's published whitepaper (March 2025) and typical automotive system characteristics.

**Q: Can I use this for other vehicle OSes?**  
A: Yes! The framework is generic. Just replace build scripts and trace event definitions.

**Q: How do I get Gitee access?**  
A: Visit https://gitee.com/ and create an account. Some repos may require approval from Halo.OS maintainers.

---

**Status**: Framework complete, CI passing, ready for real sources. 🚀

