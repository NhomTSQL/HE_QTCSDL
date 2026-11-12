# AR-IMMS Collector
Collector thu thập CPU/RAM/disk/network/uptime gửi về `/api/telemetry` mỗi 5s.
Offline: lưu queue JSONL, tự gửi bù khi có mạng.
Chạy: `python agent.py`.
Test: `python -m unittest discover -s tests -v`.
