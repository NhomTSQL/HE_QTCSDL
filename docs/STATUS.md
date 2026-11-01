# Trạng thái dự án

## Database scripts

- Đã có script tạo database, bảng, seed data, trigger/view/stored procedure và retention policy cho SQL Server.
- Script schema, index và database object hỗ trợ chạy lại; seed data bỏ qua bộ dữ liệu mẫu đã có.
- `database/06_verify_seed_data.sql` kiểm tra bộ seed và object sau khi chạy lại các script.
- Các hash mật khẩu trong seed data chỉ là placeholder; phải thay bằng hash hợp lệ trước khi dùng đăng nhập.

## Kiểm tra và review

- Kịch bản kiểm thử SQL: chạy `database/01_create_database.sql` đến `database/05_retention_policy.sql` hai lần, sau đó chạy `database/06_verify_seed_data.sql`.
- Hướng dẫn cài đồng nhất cho Windows, Docker, ODBC Driver 18, `.env`, URL-encode và kiểm tra `/health` trên hai máy: `docs/SETUP-WINDOWS.md`.
- Script smoke test endpoint: `scripts/test-health.ps1`.
- Compose bật SQL Server Agent, mount `backups/` vào container và giới hạn memory; `scripts/test-compose.ps1` kiểm tra Agent, backup/verify, host mount và hard limit.
- Docker Compose smoke test đã chạy thành công hai lần với container SQL Server: Agent `Running`, SQL Server thấy giới hạn 3072 MB, container giới hạn 4 GiB, backup được verify và file hiện trên host.
- Sau khi recreate container, database `AR_IMMS` vẫn còn; Flask `/health` kết nối Docker SQL Server thực tế và trả `healthy`.
- Đã kiểm tra cú pháp PowerShell, lỗi kết nối trả 503 qua Flask test client, và URL-encode password có ký tự đặc biệt.
- Máy thứ hai và review PR chưa được xác nhận. Trên database AR_IMMS có sẵn tại máy kiểm thử, `database/06_verify_seed_data.sql` báo thiếu `sp_record_telemetry`; chạy đầy đủ script `database/04_procedures_triggers_views.sql` trước khi chạy verifier trên database này.
- Kiểm tra SQL Server local chạy hai lượt thành công trong phiên trước.
