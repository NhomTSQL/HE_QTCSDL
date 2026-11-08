# Hướng dẫn cài đặt chung trên Windows

Thực hiện lần lượt trên mỗi máy Windows 10/11. Mỗi máy chạy một SQL Server
Developer trong Docker và một Flask API cục bộ; không dùng chung file `.env`
hoặc mật khẩu giữa các máy. Compose bật SQL Server Agent, giới hạn SQL Server
ở 3072 MB trong container 4 GiB và mount thư mục `backups/` trên host tại
`/var/opt/mssql/backups` trong container. Mục tiêu kiểm thử trên mỗi máy:
`http://localhost:5000/health` trả HTTP 200 và
`{"status":"healthy","database":"connected"}`.

## 1. Cài công cụ

Cài các công cụ sau trên từng máy:

1. Docker Desktop for Windows, dùng Linux containers; bảo đảm Docker Engine đang chạy.
2. Python 3.12 x64.
3. Microsoft ODBC Driver 18 for SQL Server x64, tải từ
   [trang chính thức của Microsoft](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server).
4. SQL Server Management Studio (SSMS) để chạy script T-SQL, tải từ
   [trang tải SSMS của Microsoft](https://learn.microsoft.com/sql/ssms/download-sql-server-management-studio-ssms).
5. Git.

Mở PowerShell mới và xác nhận Python cùng ODBC:

```powershell
py -3.12 --version
Get-OdbcDriver -Name "ODBC Driver 18 for SQL Server"
```

Sau khi tạo môi trường Python ở bước 4, xác nhận pyodbc nhận ra driver:

```powershell
.\.venv\Scripts\python.exe -c "import pyodbc; print(pyodbc.drivers())"
```

Kết quả phải có `ODBC Driver 18 for SQL Server`. Nếu chưa có, cài driver x64,
đóng/mở lại PowerShell rồi kiểm tra lại.

## 2. Lấy source và cấu hình `.env`

Clone repository rồi chuyển vào thư mục gốc:

```powershell
git clone https://github.com/NhomTSQL/HE_QTCSDL.git
Set-Location HE_QTCSDL
Copy-Item .env.example .env
```

Tạo mật khẩu riêng cho máy này. Lệnh sau in ra mật khẩu ngẫu nhiên gồm chữ hoa,
chữ thường, chữ số và ký tự đặc biệt; không commit hoặc gửi mật khẩu cho người khác:

```powershell
py -3.12 -c "import secrets,string; chars=string.ascii_letters+string.digits+'!@_-'; print(''.join(secrets.choice(chars) for _ in range(32)))"
```

Đặt mật khẩu đó vào `MSSQL_SA_PASSWORD` trong `.env`. Để cấu hình `DATABASE_URL`,
chạy lệnh sau và nhập chính mật khẩu vừa tạo khi được hỏi. Dùng `urllib.parse.quote`
để URL-encode mật khẩu, tránh lỗi khi có các ký tự như `@`, `!`, `:` hoặc `%`:

```powershell
py -3.12 -c "from getpass import getpass; from urllib.parse import quote; p=getpass('SQL Server password: '); print('DATABASE_URL=mssql+pyodbc://sa:'+quote(p,safe='')+'@localhost:1433/AR_IMMS?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes')"
```

Thay giá trị `DATABASE_URL` trong `.env` bằng nguyên dòng được in ra. Dòng đó
chứa thông tin đăng nhập; chỉ lưu trong `.env` cục bộ. Không đặt password thô
vào URL, không URL-encode giá trị `MSSQL_SA_PASSWORD`, và không chia sẻ `.env`.

Đặt `MSSQL_PORT=1433` nếu cổng này chưa được máy khác sử dụng. Nếu cần đổi cổng,
chọn một cổng trống trong `.env` và đổi cổng `1433` trong `DATABASE_URL` cho khớp.

## 3. Khởi động SQL Server và tạo schema

Trong PowerShell tại thư mục repository:

```powershell
docker compose up -d sqlserver
docker compose ps
```

Đợi trạng thái SQL Server là `healthy`. Healthcheck chỉ thành công khi SQL Server
Agent cũng đang chạy. Docker Desktop cần được cấp đủ RAM cho container 4 GiB.

Để kiểm tra Agent, giới hạn RAM, và backup mount cùng lúc, chạy:

```powershell
.\scripts\test-compose.ps1
```

Kịch bản tạo backup tạm database `master`, xác minh backup bằng
`RESTORE VERIFYONLY`, xác nhận file xuất hiện trong `backups/` trên host, rồi
xóa file kiểm thử. Kết quả mong đợi là ba dòng `PASS` cho Agent, memory limit
4 GiB và bind mount backup. Có thể chạy lại script; mỗi lượt dùng tên backup
tạm riêng. Để tạo backup giữ lại, dùng SSMS hoặc chạy T-SQL sau trên SQL Server:

```sql
BACKUP DATABASE [AR_IMMS]
TO DISK = N'/var/opt/mssql/backups/AR_IMMS.bak'
WITH INIT, CHECKSUM;
```

File sẽ có trên host tại `backups/AR_IMMS.bak`. Không dùng `docker compose down -v`
nếu cần giữ lại volume database.

Kết nối bằng SSMS tới `localhost,1433`,
chọn SQL Server Authentication, đăng nhập `sa` với mật khẩu trong `.env`; nếu
SSMS hỏi về mã hóa/chứng chỉ cho máy local, chọn tin cậy server certificate.

Mở và thực thi lần lượt các script trong SSMS:

1. `database/01_create_database.sql`
2. `database/02_create_tables.sql`
3. `database/03_seed_data.sql`
4. `database/04_procedures_triggers_views.sql`
5. `database/05_retention_policy.sql`

Chạy lại cả năm script lần thứ hai để kiểm tra khả năng chạy lại, sau đó chạy
`database/06_verify_seed_data.sql`. Kết quả mong đợi là `PASS`. Khi chạy lần đầu,
password hash trong dữ liệu mẫu chỉ là placeholder; hãy thay bằng hash hợp lệ
trước khi dùng chức năng đăng nhập.

## 4. Cài và khởi động Flask

Từ thư mục gốc repository, dùng Python 3.12 đã cài ở bước 1:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
.\.venv\Scripts\python.exe -c "import pyodbc; print(pyodbc.drivers())"
.\.venv\Scripts\python.exe backend/app.py
```

Không cần đặt `DATABASE_URL` trong terminal: Flask nạp nó từ `.env` ở thư mục gốc.
Giữ cửa sổ Flask mở khi chạy kiểm tra.

## 5. Kiểm tra `/health`

Mở PowerShell khác tại thư mục repository và chạy:

```powershell
.\scripts\test-health.ps1
```

Kịch bản kiểm thử: gửi HTTP GET tới `/health`. Kết quả mong đợi là HTTP 200 với
`status=healthy` và `database=connected`; nếu endpoint trả lỗi, JSON không đúng,
hoặc không kết nối được SQL Server, script thoát với lỗi khác 0.

Có thể kiểm tra thủ công:

```powershell
Invoke-RestMethod http://localhost:5000/health
```

Kết quả mong đợi:

```json
{"status":"healthy","database":"connected"}
```

## 6. Xác nhận trên ít nhất hai máy

Lặp lại các bước 1–5 riêng trên Máy 1 và Máy 2. Mỗi máy cần có Docker, ODBC Driver
18, database, Flask đang chạy, và phải tự chạy `.\scripts\test-health.ps1`.
Ghi lại đầu ra thành công của từng máy để nhóm xác nhận không phụ thuộc cấu hình
cá nhân.

| Máy | Người kiểm thử | Commit đã thử | Kết quả `test-health.ps1` | Thời điểm |
|---|---|---|---|---|
| Máy 1 | Chưa ghi nhận | Chưa ghi nhận | Chưa chạy trong phiên này | — |
| Máy 2 | Chưa ghi nhận | Chưa ghi nhận | Chưa chạy trong phiên này | — |

## Xử lý sự cố thường gặp

- **`Can't open lib 'ODBC Driver 18 for SQL Server'`**: cài ODBC Driver 18 x64,
  sau đó tạo lại virtual environment nếu cần.
- **Login failed hoặc sai mật khẩu**: bảo đảm `MSSQL_SA_PASSWORD` khớp password
  đã đặt khi SQL Server được tạo. Nếu volume Docker đã khởi tạo với password
  khác, sửa `.env` không thay đổi password đã lưu trong database volume.
- **SQL Server chưa sẵn sàng**: chạy `docker compose ps`, chờ healthcheck báo
  `healthy`, rồi khởi động lại Flask.
- **Sai URL khi password có ký tự đặc biệt**: tạo lại `DATABASE_URL` bằng lệnh
  URL-encode ở bước 2; chỉ nhập password nguyên dạng ở `MSSQL_SA_PASSWORD`.
- **Cổng 1433 đã được dùng**: đổi `MSSQL_PORT` và cổng trong `DATABASE_URL`
  thành cùng một cổng trống, rồi chạy `docker compose up -d`.
- **Compose config đã đổi nhưng Agent hoặc memory limit chưa cập nhật**: chạy
  `docker compose up -d --force-recreate sqlserver`. Database vẫn ở named volume;
  không xóa volume để áp dụng cấu hình.
- **SQL Server unhealthy do Agent**: kiểm tra log bằng
  `docker compose logs sqlserver`; đợi SQL Server hoàn tất khởi động, rồi chạy
  `docker compose ps` và `.\scripts\test-compose.ps1`.
- **Backup không thấy hoặc không ghi được**: bảo đảm thư mục `backups/` nằm cạnh
  `compose.yaml`, Docker Desktop có quyền truy cập repository, và T-SQL dùng
  đường dẫn trong container `/var/opt/mssql/backups`.
