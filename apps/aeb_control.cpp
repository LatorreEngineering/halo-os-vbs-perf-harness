#include "halo_tracepoints.h"

void execute_control(uint64_t frame_id, float brake_pressure) {
    tracepoint(halo, control_output, frame_id, get_monotonic_ns());
    tracepoint(halo, brake_actuate, frame_id, get_monotonic_ns(), static_cast<int32_t>(brake_pressure));
}
