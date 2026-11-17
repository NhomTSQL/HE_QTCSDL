"""Collector unit tests for Flask /telemetry endpoint."""
from __future__ import annotations

import json
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from agent import Collector
from metrics import sample_metrics


class Handler(BaseHTTPRequestHandler):
    mode = "ok"
    received = []
    headers_seen = []

    def do_POST(self):
        n = int(self.headers.get("content-length", 0))
        self.__class__.received.append(json.loads(self.rfile.read(n)))
        self.__class__.headers_seen.append(dict(self.headers))
        code = 201 if self.__class__.mode == "ok" else (422 if self.__class__.mode == "reject" else 500)
        self.send_response(code)
        self.end_headers()

    def log_message(self, *args):
        pass


class TestCollector(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), Handler)
        cls.port = cls.server.server_port
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        Handler.mode = "ok"
        Handler.received = []
        Handler.headers_seen = []

    def test_sample_metrics_contract(self):
        batch = sample_metrics(1)
        self.assertGreaterEqual(len(batch), 2)
        for item in batch:
            self.assertEqual(item["node_id"], 1)
            self.assertIn(item["metric_type"], {
                "cpu_usage_percent",
                "memory_usage_percent",
                "disk_usage_percent",
                "temperature_celsius",
            })
            self.assertIsInstance(item["value"], (int, float))
            self.assertIn(item["unit"], {"%", "C"})

    def test_submit_sends_x_api_key_header(self):
        with TemporaryDirectory() as tmp:
            c = Collector(f"http://127.0.0.1:{self.port}/telemetry", "demo-key", 1, queue_file=str(Path(tmp) / "q.jsonl"))
            payload = {"node_id": 1, "metric_type": "cpu_usage_percent", "value": 42.5, "unit": "%"}
            self.assertTrue(c.submit(payload))
            self.assertEqual(len(Handler.received), 1)
            self.assertEqual(Handler.headers_seen[0].get("X-API-Key"), "demo-key")

    def test_buffer_recovery_on_server_error(self):
        with TemporaryDirectory() as tmp:
            q = Path(tmp) / "q.jsonl"
            c = Collector(f"http://127.0.0.1:{self.port}/telemetry", "demo-key", 1, queue_file=str(q))
            payload = {"node_id": 1, "metric_type": "cpu_usage_percent", "value": 55.0, "unit": "%"}
            Handler.mode = "error"
            self.assertFalse(c.submit(payload))
            self.assertEqual(len(c.queue), 1)
            Handler.mode = "ok"
            c.flush_queue()
            self.assertEqual(len(c.queue), 0)

    def test_rejected_payload_is_dropped_not_queued(self):
        """Flask tra 4xx (sai metric_type/unit) la loi vinh vien: khong retry, khong queue."""
        with TemporaryDirectory() as tmp:
            q = Path(tmp) / "q.jsonl"
            c = Collector(f"http://127.0.0.1:{self.port}/telemetry", "demo-key", 1, queue_file=str(q))
            payload = {"node_id": 1, "metric_type": "unknown_metric", "value": 1.0, "unit": "%"}
            Handler.mode = "reject"
            self.assertFalse(c.submit(payload))
            self.assertEqual(len(Handler.received), 1, "4xx phai duoc gui 1 lan, khong retry")
            self.assertEqual(len(c.queue), 0, "payload bi tu choi khong duoc vao queue")
            self.assertFalse(q.exists(), "khong duoc ghi queue file cho payload bi tu choi")


if __name__ == "__main__":
    unittest.main()