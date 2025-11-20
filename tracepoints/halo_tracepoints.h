#undef TRACEPOINT_PROVIDER
#define TRACEPOINT_PROVIDER halo

#undef TRACEPOINT_INCLUDE
#define TRACEPOINT_INCLUDE "./halo_tracepoints.h"

#if !defined(_HALO_TRACE_H) || defined(TRACEPOINT_HEADER_MULTI_READ)
#define _HALO_TRACE_H

#include <lttng/tracepoint.h>

/* Camera ingest event */
TRACEPOINT_EVENT(
    halo,
    camera_ingest,
    TP_ARGS(uint64_t, frame_id, uint64_t, ts_ns),
    TP_FIELDS(
        ctf_integer(uint64_t, frame_id, frame_id)
        ctf_integer(uint64_t, ts_ns, ts_ns)
    )
)

/* Perception start/end */
TRACEPOINT_EVENT(
    halo,
    perception_start,
    TP_ARGS(uint64_t, frame_id, uint64_t, ts_ns),
    TP_FIELDS(
        ctf_integer(uint64_t, frame_id, frame_id)
        ctf_integer(uint64_t, ts_ns, ts_ns)
    )
)

TRACEPOINT_EVENT(
    halo,
    perception_end,
    TP_ARGS(uint64_t, frame_id, uint64_t, ts_ns),
    TP_FIELDS(
        ctf_integer(uint64_t, frame_id, frame_id)
        ctf_integer(uint64_t, ts_ns, ts_ns)
    )
)

/* Planning start/end */
TRACEPOINT_EVENT(
    halo,
    planning_start,
    TP_ARGS(uint64_t, frame_id, uint64_t, ts_ns),
    TP_FIELDS(
        ctf_integer(uint64_t, frame_id, frame_id)
        ctf_integer(uint64_t, ts_ns, ts_ns)
    )
)

TRACEPOINT_EVENT(
    halo,
    planning_end,
    TP_ARGS(uint64_t, frame_id, uint64_t, ts_ns),
    TP_FIELDS(
        ctf_integer(uint64_t, frame_id, frame_id)
        ctf_integer(uint64_t, ts_ns, ts_ns)
    )
)

/* Control output */
TRACEPOINT_EVENT(
    halo,
    control_output,
    TP_ARGS(uint64_t, frame_id, uint64_t, ts_ns),
    TP_FIELDS(
        ctf_integer(uint64_t, frame_id, frame_id)
        ctf_integer(uint64_t, ts_ns, ts_ns)
    )
)

/* Brake actuation */
TRACEPOINT_EVENT(
    halo,
    brake_actuate,
    TP_ARGS(uint64_t, frame_id, uint64_t, ts_ns, int32_t, pressure),
    TP_FIELDS(
        ctf_integer(uint64_t, frame_id, frame_id)
        ctf_integer(uint64_t, ts_ns, ts_ns)
        ctf_integer(int32_t, pressure_bar, pressure)
    )
)

/* NPU tasks for virtualization overhead */
TRACEPOINT_EVENT(
    halo,
    npu_task_begin,
    TP_ARGS(const char*, name),
    TP_FIELDS(
        ctf_string(task_name, name)
    )
)

TRACEPOINT_EVENT(
    halo,
    npu_task_end,
    TP_ARGS(const char*, name),
    TP_FIELDS(
        ctf_string(task_name, name)
    )
)

#endif /* _HALO_TRACE_H */

#include <lttng/tracepoint-event.h>
