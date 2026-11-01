# Trạng thái dự án

## Database scripts

- Đã có script tạo database, bảng, seed data, trigger/view/stored procedure và retention policy cho SQL Server.
- Script schema, index và database object hỗ trợ chạy lại; seed data bỏ qua bộ dữ liệu mẫu đã có.
- `database/06_verify_seed_data.sql` kiểm tra bộ seed và object sau khi chạy lại các script.
- Các hash mật khẩu trong seed data chỉ là placeholder; phải thay bằng hash hợp lệ trước khi dùng đăng nhập.

## Kiểm tra và review

- Kịch bản kiểm thử SQL: chạy `database/01_create_database.sql` đến `database/05_retention_policy.sql` hai lần, sau đó chạy `database/06_verify_seed_data.sql`.
- Kết quả kiểm thử thực tế và review PR: chưa xác nhận trong phiên này.
