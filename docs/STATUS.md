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

## Giao diện dashboard

Bản redesign theo phong cách Apple đã áp dụng cho `web/`:

- `web/app/globals.css`: design system dark dùng vật liệu trong mờ
  (`backdrop-filter`), system color của iOS, type scale SF (tracking âm khi
  chữ lớn), bo góc lớn, easing `--ease-spring` và `--ease-out`.
- Thanh công cụ dạng material nổi (`backdrop-filter: blur(28px)`), metric tile
  có icon màu theo trạng thái, thanh đo CPU/RAM/Disk, status pill có chấm màu
  phát sáng, chip người dùng hiển thị role.
- Tôn trọng `prefers-reduced-motion`, `prefers-reduced-transparency` và
  `prefers-contrast: more`.
- `web/app/page.tsx` giữ nguyên contract API (`/api/auth/login` → `access_token`,
  `/api/nodes`, `/api/alerts`), chỉ đổi lớp trình bày.

## Việc còn lại

- Bootstrap MVP đã chạy trên SQL Server `localhost:11433`: agent demo ACTIVE, mật khẩu dev đã đặt cục bộ.
- Backend test suite: **20/20 PASS** (`unittest`, DB thật).
- Flask test-client smoke: health/login/me/nodes/alerts/tickets/telemetry **PASS**.
- HTTP server đang chạy từ process cũ thiếu `JWT_SECRET_KEY`, nên `/auth/login` hiện trả 500; cần restart Flask sau khi nạp `.env` mới.
- Chạy smoke test HTTP sau restart Flask; sau đó kiểm tra dashboard Next.js.
- Kiểm thử trên máy thứ hai và ghi lại bằng chứng.
- Hoàn thiện demo, video và báo cáo.
- Bổ sung UI thao tác ticket/ack alert nếu cần cho demo.
