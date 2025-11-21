# Halo.OS Performance Harness - Docker Environment
# Base: Ubuntu 22.04 LTS with build tools and tracing support

FROM ubuntu:22.04

LABEL maintainer="latorre.engineering@example.com"
LABEL description="Halo.OS VBS Performance Harness - Reproducible Build Environment"
LABEL version="1.0"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ==============================================================================
# System Dependencies
# ==============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    cmake \
    ninja-build \
    ccache \
    \
    # Version control
    git \
    git-lfs \
    repo \
    \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    \
    # LTTng tracing
    lttng-tools \
    lttng-modules-dkms \
    liblttng-ust-dev \
    liblttng-ctl-dev \
    liburcu-dev \
    babeltrace2 \
    \
    # Additional tools
    curl \
    wget \
    pkg-config \
    libssl-dev \
    zlib1g-dev \
    libxml2-utils \
    xmllint \
    shellcheck \
    \
    # System utilities
    htop \
    vim \
    nano \
    less \
    tree \
    jq \
    \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# Python Environment
# ==============================================================================
# Upgrade pip and install build tools
RUN python3 -m pip install --no-cache-dir --upgrade \
    pip \
    setuptools \
    wheel

# Copy requirements and install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# ==============================================================================
# User Setup (non-root user for security)
# ==============================================================================
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USERNAME=halodev

# Create user with specific UID/GID for file permission compatibility
RUN groupadd -g ${GROUP_ID} ${USERNAME} && \
    useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash ${USERNAME} && \
    usermod -aG sudo ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# Add user to tracing group
RUN groupadd -f tracing && \
    usermod -aG tracing ${USERNAME}

# ==============================================================================
# Working Directory and Permissions
# ==============================================================================
WORKDIR /workspace
RUN chown -R ${USERNAME}:${USERNAME} /workspace

# Switch to non-root user
USER ${USERNAME}

# ==============================================================================
# Environment Variables
# ==============================================================================
ENV HOME=/home/${USERNAME}
ENV PROJECT_ROOT=/workspace
ENV BUILD_DIR=/workspace/build
ENV RESULTS_DIR=/workspace/results
ENV PATH="${HOME}/.local/bin:${PATH}"

# CMake configuration
ENV CMAKE_GENERATOR=Ninja
ENV CMAKE_BUILD_TYPE=RelWithDebInfo
ENV CMAKE_EXPORT_COMPILE_COMMANDS=ON

# Compiler cache
ENV CCACHE_DIR=/workspace/.ccache
ENV CCACHE_MAXSIZE=5G

# Python configuration
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# ==============================================================================
# Health Check
# ==============================================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 -c "import sys; sys.exit(0)" || exit 1

# ==============================================================================
# Entry Point
# ==============================================================================
# Copy entrypoint script
COPY --chown=${USERNAME}:${USERNAME} docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/bin/bash"]

# ==============================================================================
# Metadata
# ==============================================================================
LABEL org.opencontainers.image.source="https://github.com/LatorreEngineering/halo-os-vbs-perf-harness"
LABEL org.opencontainers.image.licenses="Apache-2.0"
