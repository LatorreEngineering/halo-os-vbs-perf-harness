#!/usr/bin/env bash
if [ -f /proc/device-tree/model ]; then
    MODEL=$(tr -d '\0' < /proc/device-tree/model)
    echo "Detected HW: $MODEL"
else
    MODEL=$(uname -m)
    echo "Fallback HW: $MODEL"
fi
