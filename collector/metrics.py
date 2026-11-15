"""Metric sampler using psutil. Matches Flask /telemetry and metric_types schema."""
from __future__ import annotations

import os
import sys
from typing import Any, Dict, List, Optional

try:
    import psutil
    psutil.cpu_percent(interval=None)
except ImportError:
    psutil = None


def get_disk_percent() -> Optional[float]:
    if not psutil:
        return None
    target = os.environ.get("COLLECTOR_DISK_PATH") or ("C:\\" if sys.platform.startswith("win") else "/")
    try:
        return round(float(psutil.disk_usage(target).percent), 2)
    except Exception:
        return None


def get_temperature() -> Optional[float]:
    if not psutil or not hasattr(psutil, "sensors_temperatures"):
        return None
    try:
        readings = psutil.sensors_temperatures()
        for entries in readings.values():
            if entries and entries[0].current is not None:
                return round(float(entries[0].current), 2)
    except Exception:
        pass
    return None


def sample_metrics(node_id: int) -> List[Dict[str, Any]]:
    """Tra ve danh sach metric tung dong khop voi POST /telemetry."""
    if not psutil:
        return [
            {"node_id": int(node_id), "metric_type": "cpu_usage_percent", "value": 0.0, "unit": "%"},
            {"node_id": int(node_id), "metric_type": "memory_usage_percent", "value": 0.0, "unit": "%"},
        ]

    metrics: List[Dict[str, Any]] = [
        {
            "node_id": int(node_id),
            "metric_type": "cpu_usage_percent",
            "value": round(float(psutil.cpu_percent(interval=None)), 2),
            "unit": "%",
        },
        {
            "node_id": int(node_id),
            "metric_type": "memory_usage_percent",
            "value": round(float(psutil.virtual_memory().percent), 2),
            "unit": "%",
        },
    ]

    disk = get_disk_percent()
    if disk is not None:
        metrics.append({
            "node_id": int(node_id),
            "metric_type": "disk_usage_percent",
            "value": disk,
            "unit": "%",
        })

    temp = get_temperature()
    if temp is not None:
        metrics.append({
            "node_id": int(node_id),
            "metric_type": "temperature_celsius",
            "value": temp,
            "unit": "C",
        })

    return metrics