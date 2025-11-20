#!/usr/bin/env bash
OUTFILE=${1:-env.txt}
{
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
    echo "OS: $(lsb_release -a 2>/dev/null || uname -a)"
    echo "CPU: $(lscpu | grep 'Model name')"
    echo "Memory: $(free -h)"
    echo "GPU/NPU: $(tegrastats --version 2>/dev/null || echo 'N/A')"
    echo "Docker: $(docker --version 2>/dev/null || echo 'N/A')"
    echo "Kernel: $(uname -r)"
} > "$OUTFILE"
echo "Environment info saved to $OUTFILE"
