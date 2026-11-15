# Trạng thái dự án AR-IMMS

Cập nhật: 2026-11-15

## Kiến trúc đang triển khai

- Backend/API chung của nhóm: Flask tại `backend/app.py`.
- Collector: Python + `psutil`, gửi telemetry tới Flask bằng `X-API-Key`.
- Database: SQL Server Developer trong Docker Compose.
- Nghiệp vụ telemetry: stored procedure SQL Server; Flask chỉ xác thực,
  kiểm tra payload, gọi procedure và ánh xạ lỗi HTTP.
- Next.js/Node.js chỉ là phần phát triển cục bộ trên máy cá nhân, chưa thuộc
  nhánh chung và không phải backend của bản nhóm.

Luồng chính:

```text
Python Collector → Flask REST API → Stored Procedure → SQL Server
```

## Đã có trên `develop`

- Schema SQL Server và seed: `database/01` đến `database/07`.
- Stored procedure `usp_record_telemetry` và các quy tắc cảnh báo/audit.
- Flask `GET /health`.
- Flask `POST /telemetry` với:
  - xác thực `X-API-Key`;
  - kiểm tra JSON và `node_id`;
  - gọi `dbo.usp_record_telemetry`;
  - rollback và ánh xạ lỗi stored procedure.
- Test API Flask tại `backend/test_telemetry_api.py`.
- Docker Compose chạy SQL Server Developer và SQL Server Agent.
- Collector có timeout, retry giới hạn và offline queue.

## Cách kiểm tra backend

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
.\.venv\Scripts\python.exe backend/app.py
```

Terminal khác:

```powershell
.\scripts\test-health.ps1
```

Kết quả mong đợi:

```json
{"status":"healthy","database":"connected"}
```

Chạy test API sau khi đã áp dụng schema, seed và
`database/08_dev_node_api_key.sql`:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s backend -p "test_*.py" -v
```

## Việc còn lại

- Nhóm review và chốt REST contract Flask trước khi mở rộng endpoint.
- Hoàn thiện các endpoint nghiệp vụ theo stored procedure hiện có.
- Chạy kiểm thử trên máy thứ hai và ghi lại bằng chứng.
- Hoàn thiện demo, video và báo cáo.
- Không đưa backend Node.js/Next.js cá nhân vào nhánh chung nếu chưa có quyết
  định kiến trúc mới của cả nhóm.
