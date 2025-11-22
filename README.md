# Halo.OS Open Performance Validation Harness (Nov 2025 Baseline)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)


**Goal**  
Provide a fully open-source, reproducible framework to measure end-to-end latency, jitter, and NPU virtualization overhead of Halo.OS (or any centralized vehicle OS). 

This enables independent verification (or refutation) of published numbers (~100 ms AEB latency, <3 ms jitter, 18–22 % NPU overhead).

---

## Tested Platforms

- NVIDIA Jetson AGX Orin 64 GB (JetPack 6.0)
- SemiDrive E3650 reference board
- Ubuntu 22.04 host (x86 CI runner or Docker)

---
```text
## Repo structure

halo-os-vbs-perf-harness/
├── .github/
│   └── workflows/
│       └── ci.yml                    # GitHub Actions CI/CD pipeline
│
├── ci/                               # Core automation scripts
│   ├── setup_env.sh                  # Environment setup & dependency installation
│   ├── build_halo.sh                 # Build Halo.OS with instrumentation
│   ├── run_experiment.sh             # Execute experiments with LTTng tracing
│   ├── analyze_vbs.py                # Analyze traces: latency, jitter, NPU overhead
│   ├── detect_hw.sh                  # Hardware platform detection (optional)
│   └── env_dump.sh                   # System information dump (optional)
│
├── manifests/                        # Repo tool manifests for reproducible builds
│   ├── pinned_manifest.xml           # Pinned commit SHAs (Nov 2025 baseline)
│   └── default.xml                   # Default manifest (optional)
│
├── tracepoints/                      # LTTng tracepoint definitions
│   └── halo_tracepoints.h            # Tracepoint headers for instrumentation
│
├── examples/                         # Sample data and expected outputs
│   ├── sample_events.jsonl           # Example trace event data
│   └── expected_output.txt           # Expected analysis results
│
├── docs/                             # Documentation and diagrams
│   ├── workflow.svg                  # CI/CD workflow visualization
│   └── TROUBLESHOOTING.md            # CI debugging guide
│
├── Dockerfile                        # Container environment for CI/local dev
├── docker-compose.yml                # Docker Compose orchestration
├── docker-entrypoint.sh              # Container initialization script
├── requirements.txt                  # Pinned Python dependencies
├── Makefile                          # Convenience commands (optional)
├── debug_ci.sh                       # Local CI validation script
├── .gitignore                        # Git ignore rules
├── LICENSE                           # Apache 2.0 license
└── README.md                         # This file


```text

## Overview

This repository provides a **100% open-source, reproducible framework** to measure and validate **Halo.OS performance metrics**, including:

- **End-to-end latency** (camera → brake)
- **Jitter** (99.99th percentile)
- **NPU virtualization overhead**

It is designed for **centralized vehicle OS evaluation**, allowing OEMs, Tier-1 suppliers, and researchers to independently reproduce Halo.OS performance claims versus AUTOSAR-style stacks.

All published numbers (≈100 ms AEB latency, <3 ms jitter, 18–22% NPU overhead) are fully **verifiable** without proprietary tools or NDAs.

---

## Supported Platforms

- **NVIDIA Jetson AGX Orin 64 GB** (JetPack 6.0)
- **SemiDrive E3650 reference board**
- Ubuntu **22.04 LTS** (x86 host for Docker/CI)
- Python 3.10+ (for analysis scripts)
- LTTng-UST tracing framework

---

## Repository Structure

```text


Expected Output (Nov 18, 2025 run)

Camera → Brake latency: 102.4 ms ± 8.7 ms (p50 101.2 ms, p99.99 142.1 ms)
99.99th percentile jitter: 2.7 ms
NPU virtualization overhead: 19.8 %

Key Features
	•	Fully reproducible: sync exact Halo.OS commit, no proprietary software needed
	•	Trace-based measurement: LTTng-UST ensures precise timestamps
	•	Cross-domain support: captures camera, planning, control, and NPU tasks
	•	Docker/CI ready: run x86 simulation without Jetson hardware
	•	Open-source: Apache 2.0 licensed

⸻

Contributing
	•	Open issues to share your experimental results
	•	Submit PRs for:
	•	New workloads/scenarios
	•	Improved analysis scripts
	•	CI/automation enhancements

All reproducible results, pass or fail, are welcome.

⸻

References
	•	Li Auto Halo.OS Whitepaper, March 2025
	•	Eclipse SDV Working Group, Performance Measurement Guidelines
	•	ISO 26262-8:2018, Clause 11 – Timing Analysis

⸻
## Quick Start

### Prerequisites

- Ubuntu 22.04 LTS (or Docker)
- Python 3.10+
- Git

### Local Build

```bash
# 1. Clone repository
git clone https://github.com/LatorreEngineering/halo-os-vbs-perf-harness.git
cd halo-os-vbs-perf-harness

# 2. Make scripts executable
chmod +x ci/*.sh

# 3. Build VBSPro (takes 10-15 minutes first time)
./ci/build_halo.sh

# 4. Check build artifacts
ls -lh build/

# 5. Run analysis on sample data
python3 ci/analyze_vbs.py examples/sample_events.jsonl
```

### Using Docker

```bash
# Build container
docker build -t halo-perf .

# Run build inside container
docker run --rm -v $(pwd):/workspace halo-perf ./ci/build_halo.sh

# Run analysis
docker run --rm -v $(pwd):/workspace halo-perf \
    python3 ci/analyze_vbs.py examples/sample_events.jsonl
```

### CI/CD

The repository includes GitHub Actions CI that automatically:

1. **Validates** all scripts and manifests
2. **Builds** VBSPro from Gitee sources
3. **Tests** with mock trace data
4. **Analyzes** performance metrics
5. **Reports** results

Push to `main` branch to trigger the CI pipeline.

### Expected Output

```
Camera → Brake latency: 102.4 ± 8.7 ms
  Median: 101.2 ms
  p99.99: 142.1 ms
Jitter: 2.7 ms
NPU overhead: 19.8 %
```

### Troubleshooting

**Build fails with "VBSPro not found":**
- Check Gitee connectivity: `curl -I https://gitee.com`
- Verify repo tool: `repo --version`

**CI fails with YAML errors:**
- Validate locally: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`

**Analysis produces no results:**
- Check events.jsonl format: `head -5 results/*/events.jsonl`
- Verify event names match expected format

For more help, see [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) or open an issue.


License

This project is licensed under the Apache License 2.0. See LICENSE￼ for details.



