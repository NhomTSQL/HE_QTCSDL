# Chạy migration SQL Server

Hướng dẫn cài đặt Docker, ODBC Driver 18, cấu hình `.env` và kiểm tra backend nằm tại [docs/SETUP-WINDOWS.md](../docs/SETUP-WINDOWS.md). Phân loại đầy đủ script xem [README.md](README.md).

Sau khi SQL Server khởi động, kết nối SSMS tới `localhost,1433` bằng SQL Authentication (`sa`) rồi chạy đúng thứ tự sau. Đây là **chỉ danh sách triển khai**, không bao gồm test, benchmark, reset hoặc restore drill:

1. `database/migrations/01_create_database.sql`
2. `database/migrations/02_create_tables.sql`
3. `database/migrations/03_seed_data.sql`
4. `database/migrations/04_procedures_triggers_views.sql`
5. `database/migrations/05_retention_policy.sql`
6. `database/migrations/08_dev_node_api_key.sql`
7. `database/migrations/09_auth_procedures.sql`
8. `database/migrations/10_agent_job_heartbeat.sql`
9. `database/migrations/12_backup_recovery_model.sql`
10. `database/migrations/13_backup_jobs.sql`
11. `database/migrations/14_backup_cleanup.sql`
12. `database/migrations/16_alert_dedupe.sql`
13. `database/migrations/17_dashboard_api_procedures.sql`
14. `database/migrations/19_security_and_core_fixes.sql`
15. `database/migrations/20_extended_features_procedures.sql`
16. `database/migrations/22_scale_architecture.sql`
17. `database/migrations/23_least_privilege_login.sql`
18. `database/migrations/25_password_recovery.sql`
19. `database/migrations/26_security_hardening.sql`

`02_create_tables.sql` tạo schema chuẩn hóa và nâng cấp dữ liệu trong transaction. JSON không hợp lệ, thuộc tính không nhận diện hoặc unit telemetry không nhất quán phải làm script fail/rollback.

## Kiểm chứng sau migration

- `database/tests/06_verify_seed_data.sql`
- `database/tests/07_test_normalized_schema.sql`
- `database/tests/11_test_heartbeat_job.sql`
- `database/tests/18_test_retention_batch.sql`

## Script không thuộc migration

- Benchmark: `database/benchmarks/21_performance_benchmark.sql`, `database/benchmarks/24_scale_benchmark_1m.sql`.
- Vận hành: `database/operations/15_restore_disaster_recovery.sql`.
- Reset dev phá hủy dữ liệu: `database/operations/00_reset.sql`; không chạy trên database đang dùng.

Sau khi chạy migration và đặt `AR_IMMS_DEV_PASSWORD` trong `.env`, Flask sẽ đồng bộ mật khẩu placeholder của tài khoản demo qua stored procedure.

ERD và từ điển dữ liệu: [docs/ERD-DATA-DICTIONARY.md](../docs/ERD-DATA-DICTIONARY.md).

