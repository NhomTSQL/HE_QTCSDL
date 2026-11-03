# Chạy bộ script SQL Server

Hướng dẫn cài đặt Docker, ODBC Driver 18, cấu hình `.env` và kiểm tra backend
trên nhiều máy được chuẩn hóa tại [docs/SETUP-WINDOWS.md](../docs/SETUP-WINDOWS.md).

Sau khi SQL Server khởi động, kết nối bằng SQL Server Management Studio (SSMS)
đến `localhost,1433` với SQL Authentication (`sa`) rồi chạy theo thứ tự:

1. `database/01_create_database.sql`
2. `database/02_create_tables.sql`
3. `database/03_seed_data.sql`
4. `database/04_procedures_triggers_views.sql`
5. `database/05_retention_policy.sql`

`database/02_create_tables.sql` tạo schema chuẩn hóa và nâng cấp các cột JSON/
chuỗi của schema cũ. Việc nâng cấp chạy trong transaction; JSON không hợp lệ,
thuộc tính không nhận diện hoặc đơn vị telemetry không nhất quán sẽ làm script
thất bại và rollback thay vì xóa dữ liệu không thể ánh xạ.

Để xác nhận các script an toàn khi chạy lại, chạy lại bước 1–5 lần thứ hai,
sau đó chạy `database/06_verify_seed_data.sql` và
`database/07_test_normalized_schema.sql`. Kết quả mong đợi là thông báo `PASS`
cho dữ liệu/schema, một kiểm thử nghiệp vụ hợp lệ và hai kiểm thử âm; mọi lỗi
SQL làm script kết thúc không thành công.

ERD, từ điển dữ liệu và phân tích 3NF: [docs/ERD-DATA-DICTIONARY.md](../docs/ERD-DATA-DICTIONARY.md).

Các hash mật khẩu trong seed data chỉ là placeholder. Thay chúng bằng hash hợp lệ
trước khi dùng chức năng đăng nhập.
