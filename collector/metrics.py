"""Metric sampler using psutil. Matches Flask /telemetry and metric_types schema."""
from __future__ import annotations

import json
import os
import platform
import re
import socket
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple

try:
    import psutil
    psutil.cpu_percent(interval=None)
except ImportError:
    psutil = None


def _get_disk_totals() -> Optional[Tuple[int, int]]:
    if not psutil:
        return None
    custom_path = (os.environ.get("COLLECTOR_DISK_PATH") or "").strip()
    if custom_path:
        try:
            usage = psutil.disk_usage(custom_path)
            return int(usage.used), int(usage.total)
        except Exception:
            return None

    total_used = 0
    total_size = 0
    seen_mounts = set()
    try:
        for part in psutil.disk_partitions(all=False):
            opts = (part.opts or "").lower()
            if "cdrom" in opts or not part.fstype:
                continue
            mount = part.mountpoint
            if not mount or mount in seen_mounts:
                continue
            seen_mounts.add(mount)
            try:
                usage = psutil.disk_usage(mount)
                total_used += int(usage.used)
                total_size += int(usage.total)
            except Exception:
                continue
    except Exception:
        pass

    if total_size > 0:
        return total_used, total_size

    fallback = "C:\\" if sys.platform.startswith("win") else "/"
    try:
        usage = psutil.disk_usage(fallback)
        return int(usage.used), int(usage.total)
    except Exception:
        return None


def get_disk_percent() -> Optional[float]:
    totals = _get_disk_totals()
    if not totals or totals[1] <= 0:
        return None
    return round(totals[0] * 100.0 / totals[1], 2)


def get_temperature(cpu_percent: Optional[float] = None) -> Optional[float]:
    if psutil and hasattr(psutil, "sensors_temperatures"):
        try:
            readings = psutil.sensors_temperatures()
            for entries in readings.values():
                if entries and entries[0].current is not None:
                    return round(float(entries[0].current), 2)
        except Exception:
            pass
    if os.environ.get("COLLECTOR_SIMULATE_TEMP", "1").strip().lower() not in {"0", "false", "no"}:
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


def _parse_percent(raw: str) -> float:
    match = re.search(r"([0-9]+(?:\.[0-9]+)?)", raw or "")
    return round(float(match.group(1)), 2) if match else 0.0


def _parse_memory_mb(raw: str) -> float:
    used_part = (raw or "").split("/", 1)[0].strip()
    match = re.match(r"([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]+)", used_part)
    if not match:
        return 0.0
    value = float(match.group(1))
    unit = match.group(2).lower()
    factors = {
        "b": 1.0 / (1024.0 * 1024.0),
        "kb": 1.0 / 1000.0,
        "kib": 1.0 / 1024.0,
        "mb": 1.0,
        "mib": 1.0,
        "gb": 1000.0,
        "gib": 1024.0,
        "tb": 1000.0 * 1000.0,
        "tib": 1024.0 * 1024.0,
    }
    return round(value * factors.get(unit, 1.0), 2)


def _read_docker_stats() -> Dict[str, Tuple[float, float]]:
    stats: Dict[str, Tuple[float, float]] = {}
    try:
        proc = subprocess.run(
            ["docker", "stats", "--no-stream", "--format", "{{json .}}"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if proc.returncode != 0:
            return stats
        for raw in proc.stdout.splitlines():
            line = raw.strip()
            if not line:
                continue
            entry = json.loads(line)
            cpu = _parse_percent(str(entry.get("CPUPerc", "0")))
            mem = _parse_memory_mb(str(entry.get("MemUsage", "0")))
            for key in (entry.get("ID"), entry.get("Name")):
                if isinstance(key, str) and key.strip():
                    stats[key.strip()] = (cpu, mem)
    except Exception:
        return stats
    return stats


def sample_containers(node_id: int) -> List[Dict[str, Any]]:
    """Thu thap trang thai va CPU/RAM thuc te cua Docker containers cho POST /telemetry/containers."""
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
        parsed: List[Dict[str, Any]] = []
        has_running = False
        for raw in proc.stdout.splitlines():
            line = raw.strip()
            if not line:
                continue
            info = json.loads(line)
            status = _map_docker_state(str(info.get("State", "running")))
            if status == "RUNNING":
                has_running = True
            parsed.append((info, status))

        stats = _read_docker_stats() if has_running else {}
        items: List[Dict[str, Any]] = []
        for info, status in parsed:
            cid = str(info.get("ID", ""))[:100] or "unknown"
            name = str(info.get("Names", "container"))[:100]
            cpu_pct, mem_mb = stats.get(cid) or stats.get(name) or (0.0, 0.0)
            items.append({
                "node_id": int(node_id),
                "container_id": cid,
                "name": name,
                "image": str(info.get("Image", "unknown"))[:255],
                "status": status,
                "cpu_usage_percent": cpu_pct,
                "memory_usage_mb": mem_mb,
                "restarted_count": 0,
            })
        return items
    except Exception:
        return []


def _read_cpu_model() -> str:
    if sys.platform.startswith("win"):
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\CentralProcessor\0") as key:
                val, _ = winreg.QueryValueEx(key, "ProcessorNameString")
                if isinstance(val, str) and val.strip():
                    return val.strip()[:100]
        except Exception:
            pass
    proc = platform.processor() or platform.machine() or "Unknown CPU"
    return str(proc).strip()[:100]


def sample_host_specs(node_id: int) -> Dict[str, Any]:
    """Thu thap cau hinh phan cung, OS va card mang thuc te cua may cho POST /telemetry/host."""
    disk_totals = _get_disk_totals()
    cpu_cores = int(psutil.cpu_count(logical=True) or 1) if psutil else (os.cpu_count() or 1)
    total_ram_gb = round(float(psutil.virtual_memory().total) / (1024.0 ** 3), 1) if psutil else 1.0
    total_storage_gb = round(float(disk_totals[1]) / (1024.0 ** 3), 1) if disk_totals else 1.0

    nics: List[Dict[str, Any]] = []
    primary_ip: Optional[str] = None
    primary_mac: Optional[str] = None
    if psutil:
        stats = psutil.net_if_stats()
        link_family = getattr(psutil, "AF_LINK", None)
        best_rank = -1
        for iface, addrs in psutil.net_if_addrs().items():
            ipv4 = next((a.address for a in addrs if a.family == socket.AF_INET), None)
            mac = next((a.address for a in addrs if link_family is not None and a.family == link_family), None)
            st = stats.get(iface)
            is_up = bool(st.isup) if st else False
            speed = int(st.speed) if st and st.speed is not None else None
            if not ipv4 or ipv4.startswith("127.") or (ipv4.startswith("169.254.") and not is_up):
                continue
            nics.append({
                "interface_name": iface[:100],
                "mac_address": mac[:50] if mac else None,
                "ipv4_address": ipv4[:50],
                "speed_mbps": speed,
                "is_up": is_up,
            })
            if is_up:
                lower_name = iface.lower()
                is_virtual = any(tok in lower_name for tok in ("vethernet", "wsl", "hyper-v", "tailscale", "virtual", "loopback"))
                rank = (2 if not is_virtual else 1) * 10 + (1 if mac else 0)
                if rank > best_rank:
                    best_rank = rank
                    primary_ip = ipv4
                    primary_mac = mac

    return {
        "node_id": int(node_id),
        "ip_address": primary_ip,
        "mac_address": primary_mac,
        "cpu_model": _read_cpu_model(),
        "cpu_cores": max(1, cpu_cores),
        "total_ram_gb": max(0.1, total_ram_gb),
        "total_storage_gb": max(0.1, total_storage_gb),
        "os_name": f"{platform.system()} {platform.release()}".strip()[:100],
        "os_version": (platform.version() or platform.release() or "unknown").strip()[:50],
        "nics": nics,
    }