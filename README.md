# AR-IMMS

Hệ thống giám sát và bảo trì hạ tầng Data Center (Mini Data Center testbed).
Kiến trúc: **SQL Server → Flask REST API → Next.js dashboard**, collector gửi telemetry qua HTTP.

## Cài đặt và chạy

Hướng dẫn Windows thống nhất cho nhóm — Docker Desktop, SQL Server Developer,
Microsoft ODBC Driver 18, cấu hình `.env` và URL-encode mật khẩu — nằm tại
[docs/SETUP-WINDOWS.md](docs/SETUP-WINDOWS.md). Thực hiện trên ít nhất hai máy
độc lập và ghi lại kết quả kiểm tra `/health` tại cuối tài liệu.

Tóm tắt: tạo `.env` riêng trên mỗi máy từ [.env.example](.env.example), khởi động
SQL Server bằng `docker compose up -d sqlserver`, tạo database/chạy script theo
hướng dẫn, cài dependencies rồi khởi động Flask. Xác nhận
`http://localhost:5000/health` trả về `{"status":"healthy","database":"connected"}`
bằng `.\scripts\test-health.ps1`.

Hướng dẫn chạy lại và kiểm thử script database: [database/MIGRATION_GUIDE_SQLSERVER.md](database/MIGRATION_GUIDE_SQLSERVER.md).
ERD, từ điển dữ liệu và phân tích chuẩn hóa: [docs/ERD-DATA-DICTIONARY.md](docs/ERD-DATA-DICTIONARY.md).
Smoke test Compose cho SQL Server Agent, giới hạn RAM và backup bind mount:
`.\scripts\test-compose.ps1`.

## Quy tắc dự án

- Database triển khai là SQL Server Developer; không dùng PostgreSQL/SQLite thay thế.
- Không commit `.env`, mật khẩu hoặc khóa bí mật. Mỗi máy dùng mật khẩu SQL Server riêng.
- Backend chỉ truy cập DB qua stored procedure. Next.js không kết nối SQL Server.
- Hash mật khẩu trong dữ liệu seed chỉ là placeholder; chạy `scripts/set_dev_passwords.py` trước khi đăng nhập.

## Các bước chạy

### 1. SQL Server và script database

Chờ container báo healthy. Mở SSMS hoặc Azure Data Studio, kết nối `localhost,1433` bằng `sa` và mật khẩu trong `.env`. Chạy theo thứ tự:

1. `database/01_create_database.sql`
2. `database/02_create_tables.sql`
3. `database/03_seed_data.sql`
4. `database/04_procedures_triggers_views.sql`
5. `database/05_indexes.sql`
6. `database/08_dev_node_api_key.sql`
7. `database/09_auth_procedures.sql`
8. `database/16_alert_dedupe.sql`
9. `database/17_dashboard_api_procedures.sql`

Không chạy `database/00_reset.sql` trên database đang dùng.

### 2. Backend Flask

```powershell
py -m venv .venv
.venv\Scripts\Activate.ps1
py -m pip install -r backend/requirements.txt
Copy-Item .env.example .env
# sửa DATABASE_URL và JWT_SECRET_KEY trong .env
py backend/app.py
```

Flask nạp cấu hình từ `.env` tại thư mục gốc dự án. Kiểm tra:

```powershell
Invoke-RestMethod http://localhost:5000/health
```

```json
{"status":"healthy","database":"connected"}
```

### 3. Mật khẩu demo

```powershell
py scripts/set_dev_passwords.py
```

Đặt mật khẩu cho `admin`, `operator`, `technician`. Không commit `.env` hoặc mật khẩu.

### 4. Next.js dashboard

```powershell
cd web
Copy-Item .env.example .env.local
# chỉnh BACKEND_URL nếu Flask không chạy ở localhost:5000
npm ci
npm run dev
```

Mở `http://localhost:3000`. Next.js chỉ làm BFF; mọi truy cập SQL Server đi qua Flask stored-procedure API.

### 5. Kiểm tra nhanh API

```powershell
Invoke-RestMethod http://localhost:5000/health
Invoke-RestMethod http://localhost:3000/api/health
```

Luồng MVP: đăng nhập → danh sách node kèm telemetry mới nhất → cảnh báo đang mở → ack alert/tạo ticket.

## Quy ước làm việc nhóm

| Mục | Quy ước | Ví dụ |
|---|---|---|
| Nhánh chính | `main` (không push trực tiếp) | |
| Nhánh phát triển | `develop` (không push trực tiếp) | |
| Nhánh làm việc | `feature/SCRUM-<số>-<mô-tả-ngắn>` | `feature/SCRUM-6-env-setup` |
| Commit | `SCRUM-<số>: <việc đã làm>` | `SCRUM-6: add env screenshot` |
| Pull Request | Tiêu đề `SCRUM-<số>: ...`, nhóm trưởng review rồi merge vào `develop` | |

## Quy trình mỗi lần làm việc

1. `git checkout develop` rồi `git pull`
2. `git checkout -b feature/SCRUM-<số>-<mô-tả>`
3. Code, rồi `git add .` và `git commit -m "SCRUM-<số>: ..."`
4. `git push -u origin feature/SCRUM-<số>-<mô-tả>`
5. Tạo Pull Request vào `develop`

Mục lục tài liệu, phạm vi MoSCoW và quy trình Kanban: [docs/README.md](docs/README.md).
