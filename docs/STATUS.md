# Trạng thái dự án AR-IMMS

Cập nhật: 2026-11-15

## Kiến trúc đang triển khai

- Backend/API chung của nhóm: Flask tại `backend/app.py`.
- Collector: Python + `psutil`, gửi telemetry tới Flask bằng `X-API-Key`.
- Database: SQL Server Developer trong Docker Compose.
- Nghiệp vụ telemetry: stored procedure SQL Server; Flask chỉ xác thực,
  kiểm tra payload, gọi procedure và ánh xạ lỗi HTTP.
- Next.js dashboard nằm trong `web/`, chỉ làm BFF; không kết nối SQL Server trực tiếp.
- Dashboard gọi Flask qua `BACKEND_URL`; Flask tiếp tục là API chung và là lớp duy nhất gọi stored procedure.

Luồng chính:

```text
Next.js BFF → Flask REST API → Stored Procedure → SQL Server
Python Collector ────────────→ Flask REST API
```

## MVP đã triển khai trên nhánh hiện tại

- Flask `GET /health`, `POST /telemetry`, `POST /auth/login`, `GET /auth/me`.
- Flask dashboard API: `GET /api/nodes`, `GET /api/alerts`, `POST /api/alerts/<id>/ack`,
  `GET /api/tickets`, `POST /api/tickets`, `PATCH /api/tickets/<id>/status`.
- JWT role guard cho ADMINISTRATOR, SYSTEM_OPERATOR, FIELD_TECHNICIAN.
- `database/17_dashboard_api_procedures.sql`: node snapshot, alert, acknowledge và ticket procedures.
- Next.js dashboard trong `web/`; BFF proxy tới Flask, không có `mssql`, `bcryptjs`
  hoặc truy cập DB trực tiếp.
- BFF login dùng `access_token`; telemetry giữ contract `X-API-Key` + metric normalized.
- Docker Compose chạy SQL Server Developer và SQL Server Agent.

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

Chạy test API sau khi đã áp dụng schema, seed, `database/08_dev_node_api_key.sql`,
`database/09_auth_procedures.sql`, `database/16_alert_dedupe.sql` và
`database/17_dashboard_api_procedures.sql`:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s backend -p "test_*.py" -v
```

## Cách kiểm tra frontend

```powershell
cd web
Copy-Item .env.example .env.local
npm ci
npm run build
npm run dev
```

Mở `http://localhost:3000`, đăng nhập bằng tài khoản demo đã đặt mật khẩu ở
`scripts/set_dev_passwords.py`.

## Việc còn lại

- Áp dụng `database/17_dashboard_api_procedures.sql` vào DB hiện hữu sau khi nhóm duyệt.
- Chạy smoke test `health → login → nodes/alerts/tickets → telemetry → dashboard`.
- Chạy kiểm thử trên máy thứ hai và ghi lại bằng chứng.
- Hoàn thiện demo, video và báo cáo.
- Bổ sung UI thao tác ticket/ack alert nếu cần cho demo.
