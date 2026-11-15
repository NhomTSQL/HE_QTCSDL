import os
import random
import time
from concurrent.futures import ThreadPoolExecutor

import requests

API_URL = os.environ.get("LOAD_TEST_URL", "http://localhost:5000/telemetry")
API_KEY = os.environ.get("LOAD_TEST_API_KEY", "demo-node-key-001")  # database/08_dev_node_api_key.sql
HEADERS = {"X-API-Key": API_KEY, "Content-Type": "application/json"}

# Mỗi mức tải: (req/s mục tiêu, thời gian chạy giây)
STAGES = [(10, 20), (30, 20), (50, 30)]
WORKERS = 20

# Chỉ dùng metric hợp lệ và giá trị dưới ngưỡng cảnh báo
METRICS = [
    ("cpu_usage_percent", "%", 10.0, 60.0),
    ("memory_usage_percent", "%", 20.0, 70.0),
    ("disk_usage_percent", "%", 15.0, 70.0),
    ("temperature_celsius", "C", 30.0, 60.0),
]


def send_one():
    metric, unit, lo, hi = random.choice(METRICS)
    payload = {"metric_type": metric, "value": round(random.uniform(lo, hi), 2), "unit": unit}
    start = time.perf_counter()
    try:
        resp = requests.post(API_URL, json=payload, headers=HEADERS, timeout=5)
        return resp.status_code, (time.perf_counter() - start) * 1000, None
    except Exception as exc:
        return 0, (time.perf_counter() - start) * 1000, str(exc)


def percentile(values, p):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * p / 100))]


def run_stage(rate, seconds):
    interval = 1.0 / rate
    futures, results = [], []
    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for i in range(rate * seconds):
            # giữ nhịp: request thứ i được phát vào thời điểm t0 + i*interval
            delay = t0 + i * interval - time.perf_counter()
            if delay > 0:
                time.sleep(delay)
            futures.append(pool.submit(send_one))
        results = [f.result() for f in futures]
    elapsed = time.perf_counter() - t0

    ok = [r for r in results if r[0] == 201]
    errors = {}
    for status, _, err in results:
        if status != 201:
            key = str(status) if status else f"exception: {err}"
            errors[key] = errors.get(key, 0) + 1
    lat = [r[1] for r in results]
    return {
        "target": rate, "sent": len(results), "ok": len(ok),
        "actual_rps": round(len(ok) / elapsed, 1),
        "p50": round(percentile(lat, 50), 1), "p95": round(percentile(lat, 95), 1),
        "p99": round(percentile(lat, 99), 1), "errors": errors,
    }


def main():
    print(f"Endpoint: {API_URL}")
    rows = [run_stage(rate, sec) for rate, sec in STAGES]
    print("\nmuc_tai | gui | 201 | req/s thuc te | p50 | p95 | p99 (ms) | loi")
    for r in rows:
        print(f"{r['target']:>7} | {r['sent']:>4} | {r['ok']:>4} | {r['actual_rps']:>13} | "
              f"{r['p50']:>5} | {r['p95']:>5} | {r['p99']:>5} | {r['errors'] or '-'}")
    total_ok = sum(r["ok"] for r in rows)
    print(f"\nTong request thanh cong (201): {total_ok}  -> doi chieu so dong tang them trong telemetry_metrics")
    print("KET QUA:", "PASSED" if all(not r["errors"] for r in rows) else "FAILED")


if __name__ == "__main__":
    main()