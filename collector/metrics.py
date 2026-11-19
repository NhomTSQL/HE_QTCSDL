"""Metric sampler using psutil. Matches Flask /telemetry and metric_types schema."""
from __future__ import annotations

import json
import os
import subprocess
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


def get_temperature(cpu_percent: Optional[float] = None) -> Optional[float]:
    if psutil and hasattr(psutil, "sensors_temperatures"):
        try:
            readings = psutil.sensors_temperatures()
            for entries in readings.values():
                if entries and entries[0].current is not None:
                    return round(float(entries[0].current), 2)
        except Exception:
            pass
    if os.environ.get("COLLECTOR_SIMULATE_TEMP") == "1":
        base_cpu = float(cpu_percent) if cpu_percent is not None else 25.0
        return round(38.0 + min(max(base_cpu, 0.0), 100.0) * 0.45, 2)
    return None


def sample_metrics(node_id: int) -> List[Dict[str, Any]]:
    """Tra ve danh sach metric tung dong khop voi POST /telemetry."""
    if not psutil:
        return [
            {"node_id": int(node_id), "metric_type": "cpu_usage_percent", "value": 0.0, "unit": "%"},
            {"node_id": int(node_id), "metric_type": "memory_usage_percent", "value": 0.0, "unit": "%"},
        ]

    cpu_val = round(float(psutil.cpu_percent(interval=None)), 2)
    metrics: List[Dict[str, Any]] = [
        {
            "node_id": int(node_id),
            "metric_type": "cpu_usage_percent",
            "value": cpu_val,
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

    temp = get_temperature(cpu_val)
    if temp is not None:
        metrics.append({
            "node_id": int(node_id),
            "metric_type": "temperature_celsius",
            "value": temp,
            "unit": "C",
        })

    return metrics


def _map_docker_state(state: str) -> str:
    upper = state.strip().upper()
    if upper in {"RUNNING", "STOPPED", "PAUSED", "RESTARTING", "EXITED"}:
        return upper
    if upper in {"CREATED", "DEAD", "REMOVING"}:
        return "STOPPED"
    return "RUNNING"


def sample_containers(node_id: int) -> List[Dict[str, Any]]:
    """Thu thap trang thai Docker containers qua `docker ps -a` cho POST /telemetry/containers."""
    try:
        proc = subprocess.run(
            ["docker", "ps", "-a", "--format", "{{json .}}"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        if proc.returncode != 0:
            return []
        items: List[Dict[str, Any]] = []
        for raw in proc.stdout.splitlines():
            line = raw.strip()
            if not line:
                continue
            info = json.loads(line)
            items.append({
                "node_id": int(node_id),
                "container_id": str(info.get("ID", ""))[:100] or "unknown",
                "name": str(info.get("Names", "container"))[:100],
                "image": str(info.get("Image", "unknown"))[:255],
                "status": _map_docker_state(str(info.get("State", "running"))),
                "cpu_usage_percent": 0.0,
                "memory_usage_mb": 0.0,
                "restarted_count": 0,
            })
        return items
    except Exception:
        return []