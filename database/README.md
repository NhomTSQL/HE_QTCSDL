# Database SQL Server

Thư mục này chứa T-SQL của AR-IMMS. SQL Server Developer là database duy nhất của bản nộp.

## Cấu trúc

```text
database/
├── migrations/   # triển khai theo thứ tự số hiện hữu
├── tests/        # verifier và test nghiệp vụ/schema
├── benchmarks/   # đo hiệu năng/scale, không phải migration
├── operations/   # reset dev và restore drill
├── README.md
└── MIGRATION_GUIDE_SQLSERVER.md
```

## Chạy triển khai

Chạy [MIGRATION_GUIDE_SQLSERVER.md](MIGRATION_GUIDE_SQLSERVER.md). Migration chỉ gồm `database/migrations/`; không chạy test, benchmark hoặc operations như migration.

## Phân loại file

| Nhóm | File |
|---|---|
| Migration | `migrations/01`–`05`, `08`–`10`, `12`–`14`, `16`–`17`, `19`–`20`, `22`–`23`, `25`–`26` |
| Test | `tests/06`, `07`, `11`, `18` |
| Benchmark | `benchmarks/21`, `24` |
| Operations | `operations/00_reset.sql`, `operations/15_restore_disaster_recovery.sql` |

Tên file và số thứ tự được giữ nguyên để không phá migration contract.

## An toàn

- Không chạy `operations/00_reset.sql` trên database đang dùng.
- Không chạy benchmark hoặc restore drill trên môi trường production/database dùng chung.
- Không commit `.bak`, `.trn` hoặc dữ liệu backup thật.
- Nếu migration fail, dừng và xử lý lỗi SQL; không bỏ qua bước.
- Login ứng dụng quyền tối thiểu được tạo bởi migration `23_least_privilege_login.sql`.

## Tài liệu liên quan

- [Migration guide](MIGRATION_GUIDE_SQLSERVER.md)
- [ERD và từ điển dữ liệu](../docs/ERD-DATA-DICTIONARY.md)
- [Quy ước T-SQL](../docs/CONVENTIONS.md)
- [Test backup/restore](../docs/BACKUP-TEST-CASES.md)

