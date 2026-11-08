# AR-IMMS

## Bước 1: Khởi động SQL Server và kiểm tra Flask

### Yêu cầu

- Docker Desktop đang chạy
- Python 3.10+
- Microsoft ODBC Driver 18 for SQL Server trên Windows

### 1. Tạo file môi trường

Sao chép `.env.example` thành `.env`. Đặt cùng một mật khẩu mạnh cho `MSSQL_SA_PASSWORD` và trong `DATABASE_URL` (URL-encode các ký tự đặc biệt nếu có).

### 2. Khởi động SQL Server

```powershell
docker compose up -d sqlserver
docker compose ps
```

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
