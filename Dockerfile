# Base image: Ubuntu 22.04
FROM ubuntu:22.04

LABEL maintainer="Open Auto Benchmarks"

# Non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# Install essential tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git curl wget build-essential cmake python3 python3-pip \
        lttng-tools liblttng-ust-dev tcpdump sudo pkg-config \
        python3-pandas python3-numpy iproute2 nano vim && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Copy repo scripts
COPY ci/ ./ci/
COPY tracepoints/ ./tracepoints/
COPY manifests/ ./manifests/
COPY examples/ ./examples/

# Install Python requirements
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Set entrypoint
ENTRYPOINT ["/bin/bash"]
