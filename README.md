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
Smoke test Compose cho SQL Server Agent, giới hạn RAM và backup bind mount:
`.\scripts\test-compose.ps1`.

## Quy tắc dự án

- Database triển khai là SQL Server Developer; không dùng PostgreSQL/SQLite thay thế.
- Không commit `.env`, mật khẩu hoặc khóa bí mật. Mỗi máy dùng mật khẩu SQL Server riêng.
- Hash mật khẩu trong dữ liệu seed chỉ là placeholder; thay bằng hash hợp lệ trước khi dùng chức năng đăng nhập.
