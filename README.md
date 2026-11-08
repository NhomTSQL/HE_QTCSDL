# AR-IMMS

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
- Hash mật khẩu trong dữ liệu seed chỉ là placeholder; thay bằng hash hợp lệ trước khi dùng chức năng đăng nhập.

## Tài liệu dự án

Chờ container báo healthy. Sau đó mở SQL Server Management Studio (SSMS) hoặc Azure Data Studio, kết nối tới `localhost,1433` bằng `sa` và mật khẩu trong `.env`.

Chạy theo thứ tự:

1. `database/01_create_database.sql`
2. `database/02_create_tables.sql`

Chưa chạy seed data cho tới khi password hash mẫu được thay bằng hash hợp lệ.

### 3. Cài và chạy backend

```powershell
py -m venv .venv
.venv\Scripts\Activate.ps1
py -m pip install -r backend/requirements.txt
$env:DATABASE_URL = "mssql+pyodbc://sa:YOUR_PASSWORD@localhost:1433/AR_IMMS?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes"
py backend/app.py
```

Trong terminal khác:

```powershell
Invoke-RestMethod http://localhost:5000/health
```

Kết quả mong đợi:

```json
{"status":"healthy","database":"connected"}
```

Flask nạp cấu hình từ `.env` tại thư mục gốc dự án. Có thể đặt `DATABASE_URL` trong `.env` rồi chạy `py backend/app.py`.



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
