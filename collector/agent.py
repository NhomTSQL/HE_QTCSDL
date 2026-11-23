"""AR-IMMS telemetry collector with bounded offline queue, retry, and Flask /telemetry support."""
from __future__ import annotations

import argparse
import json
import logging
import os
import time
from collections import deque
from pathlib import Path
from typing import Any, Deque, Dict, Iterable, List, Optional, Tuple

import requests

from metrics import sample_containers, sample_host_specs, sample_metrics

LOG = logging.getLogger("ar-imms-collector")


def load_env_file(env_path: str) -> None:
    """Nap bien moi truong tu file .env neu ton tai (khong ghi de bien da set san)."""
    path = Path(env_path)
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


class Collector:
    def __init__(
        self,
        api_url: str,
        api_key: str,
        node_id: int,
        interval: int = 5,
        queue_file: str = "telemetry-queue.jsonl",
        queue_max: int = 1000,
        session: Optional[requests.Session] = None,
        containers_url: Optional[str] = None,
        sync_containers: bool = False,
        batch_url: Optional[str] = None,
        use_batch: bool = False,
        host_url: Optional[str] = None,
        sync_host_specs: bool = False,
    ):
        if not api_url or not api_key or node_id <= 0:
            raise ValueError("API_URL, API_KEY and positive NODE_ID are required")
        self.api_url = api_url
        self.api_key = api_key
        self.node_id = node_id
        self.interval = max(1, interval)
        self.queue_path = Path(queue_file)
        self.queue_max = max(1, queue_max)
        self.session = session or requests.Session()
        self.containers_url = containers_url or f"{self.api_url.rstrip('/')}/containers"
        self.sync_containers = sync_containers
        self.batch_url = batch_url or f"{self.api_url.rstrip('/')}/batch"
        self.use_batch = use_batch
        self.host_url = host_url or f"{self.api_url.rstrip('/')}/host"
        self.sync_host_specs = sync_host_specs
        self.queue: Deque[Dict[str, Any]] = deque(maxlen=self.queue_max)
        self._load_queue()

    def _load_queue(self) -> None:
        if not self.queue_path.exists():
            return
        try:
            with self.queue_path.open("r", encoding="utf-8") as stream:
                for line in stream:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        self.queue.append(json.loads(line))
                    except json.JSONDecodeError:
                        LOG.warning("Ignoring corrupt queued payload")
        except OSError as exc:
            LOG.warning("Could not read queue: %s", exc)

    def _save_queue(self) -> None:
        self.queue_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.queue_path.with_suffix(self.queue_path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as stream:
            for item in self.queue:
                stream.write(json.dumps(item, separators=(",", ":")) + "\n")
        tmp.replace(self.queue_path)

    def _post_with_retry(self, url: str, body: Any) -> Tuple[str, int]:
        """Post JSON body with exponential backoff; return (outcome, status_code)."""
        delay = 0.5
        last_code = 0
        for attempt in range(4):
            try:
                response = self.session.post(
                    url,
                    json=body,
                    headers={"X-API-Key": self.api_key},
                    timeout=5,
                )
                last_code = response.status_code
                if 200 <= last_code < 300:
                    return "ok", last_code
                if 400 <= last_code < 500:
                    LOG.warning("Rejected payload (%s): %s", last_code, response.text)
                    return "rejected", last_code
            except requests.RequestException as exc:
                LOG.warning("Telemetry request failed (attempt %d): %s", attempt + 1, exc)
            if attempt < 3:
                time.sleep(delay)
                delay = min(delay * 2, 4.0)
        return "failed", last_code

    def _send(self, payload: Dict[str, Any]) -> str:
        """Gui 1 payload. Tra ve "ok", "rejected" (4xx, loi du lieu) hoac "failed" (mang/5xx).

        Phan biet 3 ket qua nay de payload bi Flask tu choi (4xx) khong bi day vao
        queue gui lai vo han, con loi tam thoi (mat mang, 5xx) thi van duoc retry.
        """
        return self._post_with_retry(self.api_url, payload)[0]

    def flush_queue(self) -> None:
        while self.queue:
            result = self._send(self.queue[0])
            if result == "failed":
                break
            # "ok" hoac "rejected": ca hai deu bo mau khoi queue; "rejected" la loi
            # du lieu vinh vien nen gui lai chi ton tai nguyen.
            if result == "rejected":
                LOG.warning("Dropping permanently rejected queued payload")
            self.queue.popleft()
            self._save_queue()

    def submit(self, payload: Dict[str, Any]) -> bool:
        self.flush_queue()
        if not self.queue:
            result = self._send(payload)
            if result == "ok":
                return True
            if result == "rejected":
                # Flask tu choi payload nay (sai metric_type/unit...): bo qua,
                # khong dua vao queue offline.
                return False
        self.queue.append(payload)
        self._save_queue()
        return False

    def submit_batch(self, payloads: Iterable[Dict[str, Any]]) -> int:
        items = list(payloads)
        if not items:
            return 0
        if not self.use_batch:
            return sum(1 for item in items if self.submit(item))

        self.flush_queue()
        if self.queue:
            self.queue.extend(items)
            self._save_queue()
            return 0

        status, code = self._post_with_retry(self.batch_url, {"metrics": items})
        if status == "ok":
            return len(items)
        if code in (404, 405):
            return sum(1 for item in items if self.submit(item))
        if status == "rejected":
            return 0

        self.queue.extend(items)
        self._save_queue()
        return 0

    def _post_optional(self, url: str, body: Any, label: str) -> bool:
        try:
            response = self.session.post(
                url,
                json=body,
                headers={"X-API-Key": self.api_key},
                timeout=5,
            )
            return 200 <= response.status_code < 300
        except requests.RequestException as exc:
            LOG.warning("%s telemetry request failed: %s", label, exc)
            return False

    def submit_containers(self, containers: List[Dict[str, Any]]) -> bool:
        if not containers:
            return True
        return self._post_optional(self.containers_url, {"containers": containers}, "Container")

    def submit_host_specs(self, specs: Dict[str, Any]) -> bool:
        return self._post_optional(self.host_url, specs, "Host specs")

    def run_forever(self) -> None:
        LOG.info("Starting collector node_id=%d -> %s (every %ds)", self.node_id, self.api_url, self.interval)
        cycle = 0
        while True:
            start = time.monotonic()
            if self.sync_host_specs and cycle % 60 == 0:
                if self.submit_host_specs(sample_host_specs(self.node_id)):
                    LOG.info("[node=%d] Synced host specs & NICs", self.node_id)
            cycle += 1
            batch: List[Dict[str, Any]] = sample_metrics(self.node_id)
            sent = self.submit_batch(batch)
            c_sent = 0
            if self.sync_containers:
                containers = sample_containers(self.node_id)
                if containers and self.submit_containers(containers):
                    c_sent = len(containers)
            summary = ", ".join(f"{m['metric_type']}={m['value']}{m['unit']}" for m in batch)
            LOG.info("[node=%d] Sent %d/%d metrics (%s)%s",
                     self.node_id, sent, len(batch), summary,
                     f" + {c_sent} containers" if self.sync_containers else "")
            remaining = self.interval - (time.monotonic() - start)
            if remaining > 0:
                time.sleep(remaining)


def _parse_bool_env(name: str, default: str = "1") -> bool:
    return os.environ.get(name, default).strip().lower() in {"1", "true", "yes"}


def main() -> int:
    parser = argparse.ArgumentParser(description="AR-IMMS Telemetry Collector")
    parser.add_argument("--env-file", default=str(Path(__file__).resolve().parent / ".env"), help="Path to .env file")
    args = parser.parse_args()

    load_env_file(args.env_file)
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    collector: Optional[Collector] = None
    try:
        api_url = os.environ.get("API_URL", "http://localhost:5000/telemetry")
        api_key = os.environ.get("API_KEY") or os.environ.get("AGENT_KEY", "")
        node_id = int(os.environ.get("NODE_ID", "0"))
        interval = int(os.environ.get("INTERVAL_SECONDS", "5"))
        queue_file = os.environ.get("QUEUE_FILE", f"telemetry-queue-node{node_id}.jsonl")
        queue_max = int(os.environ.get("QUEUE_MAX_ITEMS", "1000"))
        sync_containers = _parse_bool_env("SYNC_CONTAINERS")
        containers_url = os.environ.get("CONTAINERS_API_URL")
        use_batch = _parse_bool_env("USE_BATCH")
        batch_url = os.environ.get("BATCH_API_URL")
        sync_host_specs = _parse_bool_env("SYNC_HOST_SPECS")
        host_url = os.environ.get("HOST_API_URL")

        collector = Collector(
            api_url, api_key, node_id, interval, queue_file, queue_max,
            containers_url=containers_url, sync_containers=sync_containers,
            batch_url=batch_url, use_batch=use_batch,
            host_url=host_url, sync_host_specs=sync_host_specs,
        )
        collector.run_forever()
        return 0
    except KeyboardInterrupt:
        LOG.info("Collector stopped by user")
        return 0
    except Exception as exc:
        LOG.error("Collector failed: %s", exc)
        return 1
    finally:
        if collector is not None:
            collector.session.close()


if __name__ == "__main__":
    raise SystemExit(main())
