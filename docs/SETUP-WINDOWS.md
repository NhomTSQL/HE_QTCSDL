# Hướng dẫn cài đặt chung trên Windows

Thực hiện lần lượt trên mỗi máy Windows 10/11. Mỗi máy chạy một SQL Server
Developer trong Docker; web Next.js và collector Python chạy cục bộ.
Không dùng chung file `.env` hoặc mật khẩu giữa các máy. Compose bật SQL Server
Agent, giới hạn SQL Server ở 3072 MB trong container 4 GiB và mount thư mục
`backups/` trên host tại `/var/opt/mssql/backups` trong container.
Mục tiêu kiểm thử: `http://localhost:3000/api/health` trả HTTP 200 và
`{"status":"healthy","database":"connected"}`.

## 1. Cài công cụ

Cài các công cụ sau trên từng máy:

1. Docker Desktop for Windows, dùng Linux containers; bảo đảm Docker Engine đang chạy.
2. Node.js 20+ (LTS), tải từ https://nodejs.org.
3. Python 3.11+ (cho collector), tải từ https://python.org.
4. SQL Server Management Studio (SSMS) để chạy script T-SQL, tải từ
   [trang tải SSMS của Microsoft](https://learn.microsoft.com/sql/ssms/download-sql-server-management-studio-ssms).
5. Git.

**KHÔNG cần cài ODBC Driver.** Web truy cập SQL Server qua gói `mssql` (tedious),
không dùng ODBC.

Mở PowerShell mới và xác nhận:

```powershell
node --version     # >= 20
python --version   # >= 3.11
```

## 2. Lấy source và cấu hình `.env`

Clone repository rồi chuyển vào thư mục gốc:

```powershell
git clone https://github.com/NhomTSQL/HE_QTCSDL.git
Set-Location HE_QTCSDL
Copy-Item .env.example .env
```

Tạo mật khẩu riêng cho máy này:

```powershell
python -c "import secrets,string; chars=string.ascii_letters+string.digits+'!@_-'; print(''.join(secrets.choice(chars) for _ in range(32)))"
```

Đặt mật khẩu đó vào `MSSQL_SA_PASSWORD` trong `.env`.

## 3. Khởi động SQL Server và tạo schema

```powershell
docker compose up -d sqlserver
docker compose ps
```

Đợi trạng thái SQL Server là `healthy`.

Kết nối bằng SSMS tới `localhost,1433`, SQL Server Authentication, đăng nhập
`sa` với mật khẩu trong `.env`.

Mở và thực thi lần lượt các script trong SSMS:

1. `database/01_create_database.sql`
2. `database/02_create_tables.sql`
3. `database/03_seed_data.sql`
4. `database/04_procedures_triggers_views.sql`
5. `database/05_retention_policy.sql`

Chạy lại cả năm script lần thứ hai để kiểm tra khả năng chạy lại, sau đó chạy
`database/06_verify_seed_data.sql`. Kết quả mong đợi là `PASS`.

## 4. Cài và chạy web (Next.js)

```powershell
Set-Location web
Copy-Item .env.example .env.local
# Sửa .env.local: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, JWT_SECRET
npm install
npm run dev
```

## 5. Kiểm tra /api/health

```powershell
Invoke-RestMethod http://localhost:3000/api/health
```

Kết quả mong đợi:

```json
{"status":"healthy","database":"connected"}
```

## 6. Chạy collector

```powershell
Set-Location collector
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
Copy-Item .env.example .env
# Sửa .env: API_URL=http://localhost:3000, AGENT_KEY, NODE_ID
.\.venv\Scripts\python collector.py
```

## Xử lý sự cố thường gặp

- **Login failed hoặc sai mật khẩu**: bảo đảm `MSSQL_SA_PASSWORD` khớp password
  đã đặt khi SQL Server được tạo.
- **SQL Server chưa sẵn sàng**: chạy `docker compose ps`, chờ healthcheck báo
  `healthy`.
- **Cổng 1433 đã được dùng**: đổi `MSSQL_PORT` trong `.env`.
