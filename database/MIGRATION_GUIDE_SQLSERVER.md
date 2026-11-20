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

Sau bước 1–5, chạy tiếp các script nghiệp vụ, bảo mật, backup và mở rộng theo thứ tự:

6. `database/08_dev_node_api_key.sql`
7. `database/09_auth_procedures.sql`
8. `database/10_agent_job_heartbeat.sql`
9. `database/12_backup_recovery_model.sql`
10. `database/13_backup_jobs.sql`
11. `database/14_backup_cleanup.sql`
12. `database/16_alert_dedupe.sql`
13. `database/17_dashboard_api_procedures.sql`
14. `database/19_security_and_core_fixes.sql`
15. `database/20_extended_features_procedures.sql`
16. `database/22_scale_architecture.sql`
17. `database/23_least_privilege_login.sql`
18. `database/25_password_recovery.sql`
19. `database/26_security_hardening.sql` (bắt buộc cho `usp_validate_auth_session` và kiểm tra phiên đăng nhập)

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

Các hash mật khẩu trong seed data chỉ là placeholder. Đặt biến `AR_IMMS_DEV_PASSWORD`
trong file `.env` cục bộ để Flask tự động đồng bộ hash cho `admin`, `operator`,
`technician` khi khởi động trước khi dùng chức năng đăng nhập.
