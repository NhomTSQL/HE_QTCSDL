"""AR-IMMS telemetry collector with bounded offline queue and retry."""
from __future__ import annotations
import json, logging, os, time
from collections import deque
from pathlib import Path
from typing import Any, Deque, Dict, Optional
import requests
from metrics import sample_metrics
LOG = logging.getLogger("ar-imms-collector")
class Collector:
    def __init__(self, api_url: str, agent_key: str, node_id: int, interval: int=5, queue_file: str="telemetry-queue.jsonl", queue_max: int=1000, session: Optional[requests.Session]=None):
        if not api_url or not agent_key or node_id <= 0: raise ValueError("API_URL, AGENT_KEY and positive NODE_ID are required")
        self.api_url,self.agent_key,self.node_id=api_url,agent_key,node_id; self.interval=max(1,interval); self.queue_path=Path(queue_file); self.queue_max=max(1,queue_max); self.session=session or requests.Session(); self.queue: Deque[Dict[str,Any]]=deque(maxlen=self.queue_max); self._load_queue()
    def _load_queue(self):
        if not self.queue_path.exists(): return
        try:
            for line in self.queue_path.open("r",encoding="utf-8"):
                try: self.queue.append(json.loads(line))
                except json.JSONDecodeError: LOG.warning("Ignoring corrupt queued payload")
        except OSError as exc: LOG.warning("Could not read queue: %s",exc)
    def _save_queue(self):
        self.queue_path.parent.mkdir(parents=True,exist_ok=True); tmp=self.queue_path.with_suffix(self.queue_path.suffix+".tmp")
        with tmp.open("w",encoding="utf-8") as stream:
            for item in self.queue: stream.write(json.dumps(item,separators=(",",":"))+"\n")
        tmp.replace(self.queue_path)
    def _send(self,payload):
        delay=.5
        for attempt in range(4):
            try:
                response=self.session.post(self.api_url,json=payload,headers={"X-Agent-Key":self.agent_key},timeout=5)
                if 200 <= response.status_code < 300: return True
                if 400 <= response.status_code < 500: return False
            except requests.RequestException as exc: LOG.warning("Telemetry request failed: %s",exc)
            if attempt < 3: time.sleep(delay); delay=min(delay*2,4)
        return False
    def flush_queue(self):
        while self.queue:
            if not self._send(self.queue[0]): break
            self.queue.popleft(); self._save_queue()
    def submit(self,payload):
        self.flush_queue()
        if not self.queue and self._send(payload): return True
        self.queue.append(payload); self._save_queue(); return False
    def run_forever(self):
        while True:
            start=time.monotonic(); self.submit(sample_metrics(self.node_id)); remaining=self.interval-(time.monotonic()-start)
            if remaining > 0: time.sleep(remaining)
def main():
    logging.basicConfig(level=os.environ.get("LOG_LEVEL","INFO"),format="%(asctime)s %(levelname)s %(message)s")
    try:
        c=Collector(os.environ.get("API_URL",""),os.environ.get("AGENT_KEY",""),int(os.environ.get("NODE_ID","0")),int(os.environ.get("INTERVAL_SECONDS","5")),os.environ.get("QUEUE_FILE","telemetry-queue.jsonl"),int(os.environ.get("QUEUE_MAX_ITEMS","1000"))); c.run_forever()
    except KeyboardInterrupt: return 0
    except Exception as exc: LOG.error("Collector failed: %s",exc); return 1
if __name__ == "__main__": raise SystemExit(main())
