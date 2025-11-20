#include "halo_tracepoints.h"

void plan(uint64_t frame_id) {
    tracepoint(halo, planning_start, frame_id, get_monotonic_ns());
    // Path planning & trajectory generation
    compute_trajectory(frame_id);
    tracepoint(halo, planning_end, frame_id, get_monotonic_ns());
}
