#include "halo_tracepoints.h"
#include <chrono>
#include <cstdint>

uint64_t get_monotonic_ns() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()
    ).count();
}

void process_camera_frame(uint64_t frame_id, const CameraFrame& frame) {
    tracepoint(halo, camera_ingest, frame_id, get_monotonic_ns());

    tracepoint(halo, perception_start, frame_id, get_monotonic_ns());
    // Simulate perception processing
    detect_objects(frame);
    tracepoint(halo, perception_end, frame_id, get_monotonic_ns());
}

void detect_objects(const CameraFrame& frame) {
    // AI inference code
}
