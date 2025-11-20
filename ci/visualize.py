#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt
import sys

df = pd.read_json(sys.argv[1], lines=True)
ingest = df[df['name'] == 'halo_camera_ingest'].set_index('frame_id')['time']
actuate = df[df['name'] == 'halo_brake_actuate'].set_index('frame_id')['time']
lat_ms = (actuate - ingest) / 1e6

plt.figure(figsize=(10,5))
plt.plot(lat_ms.values, marker='o')
plt.title("Camera → Brake Latency")
plt.xlabel("Frame")
plt.ylabel("Latency (ms)")
plt.grid(True)
plt.savefig("latency_plot.png")
plt.show()
