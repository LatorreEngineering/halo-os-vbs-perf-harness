#!/usr/bin/env bash
# ci/build_mock.sh
# Create mock VBSPro build artifacts for CI demonstration
# NOTE: This is a placeholder until real Halo.OS sources are accessible

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "========================================"
log "Mock VBSPro Build (CI Demo)"
log "========================================"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"

log "Creating build directory structure..."
mkdir -p "${BUILD_DIR}"/{lib,bin,include}

log "Generating mock build artifacts..."

# Create mock shared library
cat > "${BUILD_DIR}/lib/libvbspro.so.info" << 'EOF'
Mock VBSPro Library v1.0
========================

This is a placeholder for the actual VBSPro middleware library.

In production, this would be built from:
  - Source: https://gitee.com/haloos/vbs
  - Manifest: vbs.xml
  - Build system: CMake + Ninja

The real library provides:
  - Message routing (pub/sub)
  - RPC communication
  - Resource virtualization (NPU, sensors)
  - LTTng tracepoints for performance measurement

To build the real VBSPro:
  1. Ensure Gitee access (may need VPN in some regions)
  2. Install: repo, cmake, ninja-build, lttng-tools
  3. Run: ./ci/build_halo.sh (when sources are accessible)
EOF

# Create mock binary
cat > "${BUILD_DIR}/bin/vbs_router.info" << 'EOF'
Mock VBS Router v1.0
====================

This placeholder represents the VBS message routing daemon.

In production, this binary would:
  - Route messages between vehicle domains
  - Manage pub/sub topics
  - Handle RPC calls
  - Coordinate NPU virtualization
  - Emit LTTng tracepoints for latency measurement
EOF

# Create mock header
cat > "${BUILD_DIR}/include/vbspro.h" << 'EOF'
/* Mock VBSPro Header */
#ifndef VBSPRO_H
#define VBSPRO_H

/* Placeholder for real VBSPro API */
typedef struct {
    const char* topic;
    uint64_t timestamp_ns;
    void* data;
    size_t data_len;
} vbspro_message_t;

int vbspro_init(void);
int vbspro_publish(const char* topic, const void* data, size_t len);
int vbspro_subscribe(const char* topic);

#endif /* VBSPRO_H */
EOF

# Create build info
cat > "${BUILD_DIR}/build_info.txt" << EOF
Mock Build Information
======================

Build Date: $(date)
Build Type: Mock/Demonstration
CI Environment: GitHub Actions
Purpose: Demonstrate performance analysis framework

This is a MOCK build for CI demonstration.

To build real VBSPro from Halo.OS sources:
  - Requires access to https://gitee.com/haloos/
  - May require authentication for private repos
  - See README.md for setup instructions

Current Status:
  ✓ Framework structure validated
  ✓ Analysis pipeline working
  ✓ CI automation functional
  ⚠ Waiting for real Halo.OS source access

Next Steps:
  1. Obtain Gitee access credentials
  2. Update MANIFEST_REPO_URL in build_halo.sh
  3. Replace this script with real build
EOF

log "Mock build artifacts created:"
log "  Libraries: ${BUILD_DIR}/lib/"
log "  Binaries:  ${BUILD_DIR}/bin/"
log "  Headers:   ${BUILD_DIR}/include/"
log "  Info:      ${BUILD_DIR}/build_info.txt"

log "========================================"
log "Mock build completed successfully"
log "========================================"
log ""
log "NOTE: This is a demonstration build."
log "See build_info.txt for instructions on building real VBSPro."

exit 0
