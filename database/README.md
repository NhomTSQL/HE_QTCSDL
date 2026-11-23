# Database SQL Server

Thư mục này chứa toàn bộ T-SQL của AR-IMMS. Database triển khai và bản nộp là **SQL Server Developer**.

## Cấu trúc

```text
database/
├── canonical/           # 19 script chạy lần đầu để thiết lập database
├── verification/
│   ├── tests/           # 4 script kiểm thử schema, dữ liệu, job, retention
│   ├── benchmarks/      # 2 script đo hiệu năng (không chạy trong cài đặt)
│   └── operations/      # reset dev và restore drill (không chạy tự động)
├── legacy/              # 27 script gốc giữ lại làm lịch sử và nâng cấp database đã cài
├── README.md
└── MIGRATION_GUIDE_SQLSERVER.md
```

## Cài đặt database

Chạy cho từng lần cài mới trên SQL Server Developer:

```powershell
# Đối với container SQL Server hiện đang chạy
.\scripts\setup-database.ps1 -Database AR_IMMS -Server localhost,1433 -Credential (Get-Credential)
```

Hoặc dùng kiểm tra khô mà không chạy SQL:

```powershell
.\scripts\setup-database.ps1 -DryRun
```

### Thứ tự deploy

`database/canonical/` chứa đúng thứ tự an toàn:

1. `01_create_database.sql`
2. `02_create_tables.sql`
3. `03_seed_data.sql`
4. `04_procedures_triggers_views.sql`
5. `05_retention_policy.sql`
6. `08_dev_node_api_key.sql`
7. `09_auth_procedures.sql`
8. `10_agent_job_heartbeat.sql`
9. `12_backup_recovery_model.sql`
10. `13_backup_jobs.sql`
11. `14_backup_cleanup.sql`
12. `16_alert_dedupe.sql`
13. `17_dashboard_api_procedures.sql`
14. `19_security_and_core_fixes.sql`
15. `20_extended_features_procedures.sql`
16. `22_scale_architecture.sql`
17. `23_least_privilege_login.sql`
18. `25_password_recovery.sql`
19. `26_security_hardening.sql`

Script reset, kiểm thử, benchmark và restore drill **không chạy trong cài đặt chuẩn** và nằm ở `database/verification/`.

## An toàn

- Không chạy `database/verification/operations/00_reset.sql` trên database đang dùng.
- Backup có thể chứa dữ liệu nhạy cảm; không commit file `.bak`, `.trn`.
- Nếu migration/lỗi SQL, dừng và xử lý nguyên nhân; không bỏ qua bước.

## Lịch sử

Tất cả 27 script gốc giữ nguyên nội dung trong `database/legacy/` để đối chiếu hoặc nâng cấp database đã cài.

