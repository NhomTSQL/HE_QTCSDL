# Documentation Guide

Bộ tài liệu AR-IMMS được chia theo người đọc và nhiệm vụ. Không dùng một file duy nhất để chứa cả phạm vi, cách chạy, schema và báo cáo kiểm thử.

## Bắt đầu từ đâu?

| Bạn cần làm gì? | Đọc trước |
|---|---|
| Clone và chạy local | [README.md](../README.md) → [SETUP-WINDOWS.md](SETUP-WINDOWS.md) |
| Hiểu luồng hệ thống | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Cài SQL Server database | [database/README.md](../database/README.md) → [database/MIGRATION_GUIDE_SQLSERVER.md](../database/MIGRATION_GUIDE_SQLSERVER.md) |
| Hiểu bảng/quan hệ/3NF | [ERD-DATA-DICTIONARY.md](ERD-DATA-DICTIONARY.md) → [DATABASE-SPECIFICATION.md](DATABASE-SPECIFICATION.md) |
| Vận hành backup/restore/Agent | [OPERATION-GUIDE.md](OPERATION-GUIDE.md) → [BACKUP-TEST-CASES.md](BACKUP-TEST-CASES.md) |
| Chạy hoặc viết test | [TEST-PLAN-AND-REPORT.md](TEST-PLAN-AND-REPORT.md) |
| Chuẩn bị demo/vấn đáp | [DEMO.md](DEMO.md) |
| Dùng dashboard | [USER-MANUAL.md](USER-MANUAL.md) |
| Kiểm tra phạm vi/tiến độ | [SCOPE-MOSCOW.md](SCOPE-MOSCOW.md) → [STATUS.md](STATUS.md) |
| Sửa code hoặc T-SQL | [../CLAUDE.md](../CLAUDE.md) → [CONVENTIONS.md](CONVENTIONS.md) |

## Quy tắc nguồn sự thật

- **Cách chạy:** `README.md`, `SETUP-WINDOWS.md`, `database/MIGRATION_GUIDE_SQLSERVER.md`.
- **Cấu trúc và luồng:** `ARCHITECTURE.md`.
- **Database:** `database/README.md`, `DATABASE-SPECIFICATION.md`, ERD/data dictionary và T-SQL hiện hữu.
- **Test evidence:** `TEST-PLAN-AND-REPORT.md`, `STATUS.md`, log/kịch bản thực tế.
- **Scope:** `SCOPE-MOSCOW.md`; backlog Jira là kế hoạch, không tự động là bằng chứng hoàn thành.
- **Development rules:** `CLAUDE.md`, `CONVENTIONS.md`.

Nếu hai tài liệu mâu thuẫn, không đoán. Kiểm tra code/script trước, sửa tài liệu nguồn sự thật, rồi cập nhật các tài liệu dẫn chiếu liên quan.

## Cách ghi trạng thái

Phân biệt rõ:

- **Implemented:** mã nguồn/script đã tồn tại.
- **Verified:** đã chạy lệnh/kịch bản trong môi trường cụ thể và có kết quả.
- **Blocked:** chưa thể kiểm chứng do thiếu SQL Server, dependency hoặc máy thứ hai.
- **Historical:** kết quả ở commit/ngày cũ, không đại diện cho HEAD hiện tại.

Không ghi số PASS lịch sử như kết quả hiện tại nếu chưa chạy lại.

