# Trạng thái dự án

## Database scripts

- Schema SQL Server có ERD/từ điển dữ liệu và phân tích 3NF tại `docs/ERD-DATA-DICTIONARY.md`.
- `database/02_create_tables.sql` tạo 25 bảng; schema tách RBAC, metric/unit, marker coordinates và NIC thành các quan hệ riêng.
- Khi nâng cấp schema cũ, script chuyển JSON/chuỗi trong transaction; dữ liệu không ánh xạ được gây lỗi và rollback thay vì bị bỏ âm thầm.
- Script schema, index và database object hỗ trợ chạy lại; seed data thêm các hàng còn thiếu.
- `database/06_verify_seed_data.sql` kiểm tra seed/schema; `database/07_test_normalized_schema.sql` kiểm tra SP với dữ liệu hợp lệ, đơn vị sai và metric không tồn tại.
- Các hash mật khẩu trong seed data chỉ là placeholder; phải thay bằng hash hợp lệ trước khi dùng đăng nhập.

## Kiểm tra và review

- SQL Server Express: thiết lập mới chạy script 01–05 hai lượt, sau đó `06` và `07` đều PASS.
- SQL Server Express: tạo schema cũ từ commit trước, chạy nâng cấp 02 và seed/object mới hai lượt; dữ liệu quyền, tọa độ, metric và NIC được giữ lại; `06`/`07` đều PASS.
- Hướng dẫn cài đồng nhất cho Windows, Docker, ODBC Driver 18, `.env`, URL-encode và kiểm tra `/health` trên hai máy: `docs/SETUP-WINDOWS.md`.
- Script smoke test endpoint: `scripts/test-health.ps1`.
- Compose bật SQL Server Agent, mount `backups/` vào container và giới hạn memory; `scripts/test-compose.ps1` kiểm tra Agent, backup/verify, host mount và hard limit.
- Docker Compose smoke test đã chạy thành công hai lần với container SQL Server: Agent `Running`, SQL Server thấy giới hạn 3072 MB, container giới hạn 4 GiB, backup được verify và file hiện trên host.
- Sau khi recreate container, database `AR_IMMS` vẫn còn; Flask `/health` kết nối Docker SQL Server thực tế và trả `healthy`.
- Đã kiểm tra cú pháp PowerShell, lỗi kết nối trả 503 qua Flask test client, và URL-encode password có ký tự đặc biệt.
- Review PR và chạy thử trên máy thứ hai còn chờ nhóm xác nhận.
