"""Collector smoke tests."""
from __future__ import annotations
import json, sys, threading, unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from agent import Collector
from metrics import sample_metrics
class Handler(BaseHTTPRequestHandler):
    mode="ok"; received=[]
    def do_POST(self):
        n=int(self.headers.get("content-length",0)); self.__class__.received.append(json.loads(self.rfile.read(n)))
        self.send_response(201 if self.__class__.mode=="ok" else (400 if self.__class__.mode=="reject" else 500)); self.end_headers()
    def log_message(self,*args): pass
class TestCollector(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=HTTPServer(("127.0.0.1",0),Handler); cls.port=cls.server.server_port; threading.Thread(target=cls.server.serve_forever,daemon=True).start()
    @classmethod
    def tearDownClass(cls): cls.server.shutdown()
    def setUp(self): Handler.mode="ok"; Handler.received=[]
    def test_sample_metrics_contract(self):
        data=sample_metrics(1); self.assertEqual(data["node_id"],1); self.assertIn("T",data["collected_at"]); self.assertIn("Z",data["collected_at"]); self.assertTrue(0<=data["cpu_usage_percent"]<=100)
    def test_submit_success(self):
        with TemporaryDirectory() as tmp:
            c=Collector(f"http://127.0.0.1:{self.port}/telemetry","key",1,queue_file=str(Path(tmp)/"q")); self.assertTrue(c.submit({"node_id":1})); self.assertEqual(len(Handler.received),1)
    def test_buffer_recovery(self):
        with TemporaryDirectory() as tmp:
            q=Path(tmp)/"q"; c=Collector(f"http://127.0.0.1:{self.port}/telemetry","key",1,queue_file=str(q)); Handler.mode="error"; self.assertFalse(c.submit({"node_id":1})); self.assertEqual(len(c.queue),1); Handler.mode="ok"; c.flush_queue(); self.assertEqual(len(c.queue),0)
if __name__ == "__main__": unittest.main()
