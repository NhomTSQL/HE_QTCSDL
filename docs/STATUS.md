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
- Đã kiểm tra cú pháp PowerShell, đầu ra healthy của script smoke test, phản hồi `/health` 200/503 bằng Flask test client, và URL-encode password có ký tự đặc biệt.
- Docker Engine không chạy trong môi trường hiện tại; kiểm thử Docker thật, xác nhận `/health` trên hai máy và review PR vẫn cần nhóm thực hiện.
- Kiểm tra SQL Server local chạy hai lượt thành công trong phiên trước.
