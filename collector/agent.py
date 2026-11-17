"""AR-IMMS telemetry collector with bounded offline queue, retry, and Flask /telemetry support."""
from __future__ import annotations

import argparse
import json
import logging
import os
import time
from collections import deque
from pathlib import Path
from typing import Any, Deque, Dict, Iterable, List, Optional

import requests

from metrics import sample_metrics

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
        self.queue: Deque[Dict[str, Any]] = deque(maxlen=self.queue_max)
        self._load_queue()

    def _load_queue(self) -> None:
        if not self.queue_path.exists():
            return
        try:
            for line in self.queue_path.open("r", encoding="utf-8"):
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

    def _send(self, payload: Dict[str, Any]) -> str:
        """Gui 1 payload. Tra ve "ok", "rejected" (4xx, loi du lieu) hoac "failed" (mang/5xx).

        Phan biet 3 ket qua nay de payload bi Flask tu choi (4xx) khong bi day vao
        queue gui lai vo han, con loi tam thoi (mat mang, 5xx) thi van duoc retry.
        """
        delay = 0.5
        for attempt in range(4):
            try:
                response = self.session.post(
                    self.api_url,
                    json=payload,
                    headers={"X-API-Key": self.api_key},
                    timeout=5,
                )
                if 200 <= response.status_code < 300:
                    return "ok"
                if 400 <= response.status_code < 500:
                    LOG.warning("Rejected payload (%s): %s", response.status_code, response.text)
                    return "rejected"
            except requests.RequestException as exc:
                LOG.warning("Telemetry request failed (attempt %d): %s", attempt + 1, exc)
            if attempt < 3:
                time.sleep(delay)
                delay = min(delay * 2, 4.0)
        return "failed"

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
        sent = 0
        for item in payloads:
            if self.submit(item):
                sent += 1
        return sent

    def run_forever(self) -> None:
        LOG.info("Starting collector node_id=%d -> %s (every %ds)", self.node_id, self.api_url, self.interval)
        while True:
            start = time.monotonic()
            batch: List[Dict[str, Any]] = sample_metrics(self.node_id)
            sent = self.submit_batch(batch)
            summary = ", ".join(f"{m['metric_type']}={m['value']}{m['unit']}" for m in batch)
            LOG.info("[node=%d] Sent %d/%d metrics (%s)", self.node_id, sent, len(batch), summary)
            remaining = self.interval - (time.monotonic() - start)
            if remaining > 0:
                time.sleep(remaining)


def main() -> int:
    parser = argparse.ArgumentParser(description="AR-IMMS Telemetry Collector")
    parser.add_argument("--env-file", default=str(Path(__file__).resolve().parent / ".env"), help="Path to .env file")
    args = parser.parse_args()

    load_env_file(args.env_file)
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    try:
        api_url = os.environ.get("API_URL", "http://localhost:5000/telemetry")
        api_key = os.environ.get("API_KEY") or os.environ.get("AGENT_KEY", "")
        node_id = int(os.environ.get("NODE_ID", "0"))
        interval = int(os.environ.get("INTERVAL_SECONDS", "5"))
        queue_file = os.environ.get("QUEUE_FILE", f"telemetry-queue-node{node_id}.jsonl")
        queue_max = int(os.environ.get("QUEUE_MAX_ITEMS", "1000"))

        collector = Collector(api_url, api_key, node_id, interval, queue_file, queue_max)
        collector.run_forever()
    except KeyboardInterrupt:
        LOG.info("Collector stopped by user")
        return 0
    except Exception as exc:
        LOG.error("Collector failed: %s", exc)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())