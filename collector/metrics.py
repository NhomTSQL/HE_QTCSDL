"""Metric sampler using psutil. Complies with docs/API.md contract."""
from __future__ import annotations
import datetime as _dt
import os
import sys
import time
from typing import Any, Dict, Optional
try:
    import psutil
except ImportError:
    psutil = None

def get_disk_percent() -> Optional[float]:
    if not psutil: return None
    target = os.environ.get("COLLECTOR_DISK_PATH") or ("C:\\" if sys.platform.startswith("win") else "/")
    try: return round(float(psutil.disk_usage(target).percent), 2)
    except Exception: return None

def get_temperature() -> Optional[float]:
    if not psutil or not hasattr(psutil, "sensors_temperatures"): return None
    try:
        readings = psutil.sensors_temperatures()
        for entries in readings.values():
            if entries and entries[0].current is not None: return round(float(entries[0].current), 2)
    except Exception: pass
    return None

def sample_metrics(node_id: int) -> Dict[str, Any]:
    collected_at = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if not psutil:
        return {"node_id": node_id, "collected_at": collected_at, "cpu_usage_percent": 0.0, "memory_usage_percent": 0.0, "disk_usage_percent": None, "temperature_celsius": None, "network_in_bytes": 0, "network_out_bytes": 0, "uptime_seconds": 0, "process_count": 0}
    disk = get_disk_percent()
    net = psutil.net_io_counters()
    return {"node_id": int(node_id), "collected_at": collected_at, "cpu_usage_percent": round(float(psutil.cpu_percent()), 2), "memory_usage_percent": round(float(psutil.virtual_memory().percent), 2), "disk_usage_percent": disk, "temperature_celsius": get_temperature(), "network_in_bytes": int(net.bytes_recv) if net else 0, "network_out_bytes": int(net.bytes_sent) if net else 0, "uptime_seconds": max(0, int(time.time() - psutil.boot_time())), "process_count": len(psutil.pids())}
