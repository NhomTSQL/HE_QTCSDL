# Đặc tả database SQL Server

## Nguyên tắc

- SQL Server Developer là database duy nhất của bản nộp.
- Backend gọi stored procedure; schema và quyền bảo vệ invariant ở database.
- Tên bảng hiện hữu giữ nguyên; object mới tuân theo `usp_`, `ufn_`, `vw_`, `trg_`.
- Thời gian dùng UTC `datetime2(0)` khi phù hợp nghiệp vụ.

## Các lớp database

1. **Schema lõi:** users/roles/permissions, hierarchy Site/Room/Rack/Node, metric types và telemetry.
2. **Nghiệp vụ:** alerts, tickets, containers, markers, asset/warranty/maintenance và notifications.
3. **Bảo mật/phiên:** audit logs, collector agents, auth sessions, MFA/recovery và shift handover.
4. **Vận hành/scale:** latest snapshot, staging/archive, partition function/scheme, columnstore và index vận hành.

Danh sách chi tiết bảng và quan hệ nằm tại [ERD-DATA-DICTIONARY.md](ERD-DATA-DICTIONARY.md).

## Stored procedure boundary

Backend không nhúng truy vấn nghiệp vụ. Các nhóm procedure gồm:

- health/authentication/session;
- collector API key và telemetry đơn/batch;
- hierarchy, node/container/marker;
- alert, ticket và notification;
- asset/warranty/maintenance;
- analytics/capacity/history;
- user/role/agent/audit;
- retention, partition purge và backup operation.

Procedure có nhiều bước ghi phải xác định transaction boundary và rollback khi lỗi. Trigger audit/invariant phải xử lý multi-row.

## Hiệu năng và bảo vệ dữ liệu

- `node_latest_metrics` phục vụ đọc snapshot mới nhất.
- `telemetry_metrics` có partition theo tháng khi script scale được áp dụng.
- `NCCI_telemetry_analytics` phục vụ tổng hợp analytics quy mô lớn.
- Login ứng dụng `ar_imms_app` dùng role quyền tối thiểu theo script tương ứng.
- Index chỉ được đánh giá cùng truy vấn mục tiêu và số đo IO/thời gian.

## Cài đặt và kiểm chứng

- Cài theo [database/README.md](../database/README.md) và [MIGRATION_GUIDE_SQLSERVER.md](../database/MIGRATION_GUIDE_SQLSERVER.md).
- ERD/3NF: [ERD-DATA-DICTIONARY.md](ERD-DATA-DICTIONARY.md).
- Backup/restore: [BACKUP-TEST-CASES.md](BACKUP-TEST-CASES.md).
- Không gọi benchmark, restore drill hoặc reset là migration thường.


