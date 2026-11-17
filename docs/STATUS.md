# Trạng thái dự án AR-IMMS

Cập nhật: 2026-11-17

## Kiến trúc đang triển khai

- Backend/API chung: Flask tại `backend/app.py`.
- Collector: Python + `psutil`, gửi telemetry tới Flask bằng `X-API-Key`.
- Database: SQL Server Developer trong Docker Compose.
- Nghiệp vụ telemetry: stored procedure SQL Server; Flask chỉ xác thực,
  kiểm tra payload, gọi procedure và ánh xạ lỗi HTTP.
- Next.js dashboard trong `web/`, chỉ làm BFF; không kết nối SQL Server trực tiếp.

```text
Next.js BFF → Flask REST API → Stored Procedure → SQL Server
Python Collector ────────────→ Flask REST API
```

## MVP đã triển khai trên nhánh hiện tại

- Flask `GET /health`, `POST /telemetry`, `POST /auth/login`, `GET /auth/me`.
- Flask dashboard API: nodes, alerts, acknowledge và tickets.
- JWT role guard cho ADMINISTRATOR, SYSTEM_OPERATOR, FIELD_TECHNICIAN.
- `database/17_dashboard_api_procedures.sql`: node snapshot, alert và ticket procedures.
- Next.js dashboard có đọc dữ liệu và UI thao tác acknowledgement/ticket theo role.
- Collector nằm trong `collector/`: CPU/RAM/disk, queue JSONL offline, retry/backoff,
  test HTTP cục bộ. Endpoint đúng là `POST /telemetry`.
- Docker Compose chạy SQL Server Developer và SQL Server Agent.

## Cách kiểm tra

Backend:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
.\.venv\Scripts\python.exe backend/app.py
```

Collector:

```powershell
.\.venv\Scripts\python.exe -m pip install -r collector/requirements.txt
Copy-Item collector/.env.example collector/.env
.\.venv\Scripts\python.exe -m unittest discover -s collector/tests -v
.\.venv\Scripts\python.exe collector/agent.py
```

`collector/.env` và `telemetry-queue*.jsonl` không commit. API key không ghi vào
repo; key phải là agent ACTIVE trong SQL Server.

## Bằng chứng hiện tại (kiểm chứng 2026-11-17)

- Flask `GET /health`: **PASS** → `{"status":"healthy","database":"connected"}`.
- Collector unit tests: **4/4 PASS**
  (`python -m unittest discover -s collector/tests -v`), gồm metric contract,
  header `X-API-Key`, queue recovery khi 5xx/mất mạng, và payload bị 4xx thì bị bỏ
  (không retry, không vào queue).
- Collector CLI end-to-end với stub server: **PASS** — 12 payload, đúng path
  `/telemetry`, đúng key, queue rỗng sau khi gửi thành công.
- Offline queue qua lần khởi động lại: **PASS** — ghi JSONL khi mất mạng, nạp lại
  và flush sạch khi server trở lại.
- Live end-to-end thật (collector CLI → Flask `POST /telemetry` → SQL Server):
  **PASS** — `telemetry_metrics` của node 1 tăng 9 dòng trong 8 giây, không còn
  payload tồn trong queue; đọc lại thấy `cpu_usage_percent`,
  `memory_usage_percent`, `disk_usage_percent` với timestamp UTC mới.
- Flask từ chối đúng hợp đồng: thiếu key → `401`, body sai → `400`,
  `node_id` không khớp key → `403` (cả ba không ghi DB).
- Backend suite: `20 tests`, **OK (skipped=14)** khi không có
  `AR_IMMS_DEV_PASSWORD`; 6 test không cần mật khẩu vẫn chạy. Chỉ ghi `20/20`
  khi chạy lại với biến môi trường đó.

## Việc còn lại

- Chạy backend suite đầy đủ với `AR_IMMS_DEV_PASSWORD` để xác nhận 20/20.
- Smoke dashboard Next.js (login + ack/ticket) với tài khoản demo; chưa chạy
  trong lượt này vì cần thao tác ghi dữ liệu thật.
- Kiểm thử trên máy thứ hai và ghi bằng chứng.
- Hoàn thiện demo, video và báo cáo.
