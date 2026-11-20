# Trạng thái dự án AR-IMMS

Cập nhật: 2026-11-20

## Kiến trúc đang triển khai

- Backend/API chung: Flask tại `backend/app.py` và `backend/dashboard_api.py` (kích hoạt connection pool `pool_size=15`, `max_overflow=25`, `pool_pre_ping=True`).
- Collector: Python + `psutil`, gửi telemetry theo batch (`POST /telemetry/batch`, mặc định `USE_BATCH=1`, tự fallback `POST /telemetry` nếu endpoint chưa bật) và trạng thái container (`POST /telemetry/containers`) tới Flask bằng `X-API-Key`.
- Database: SQL Server 2022 Developer trong Docker Compose (**32 bảng**: `25` bảng nghiệp vụ chuẩn hóa 3NF + `2` bảng mở rộng `node_latest_metrics`, `telemetry_metrics_archive_staging` + `5` bảng bảo mật/phiên/bàn giao ca `auth_sessions`, `account_access_requests`, `password_recovery_codes`, `mfa_backup_codes`, `shift_handover_notes`), phân vùng theo tháng và Columnstore index `NCCI_telemetry_analytics`.
- Nghiệp vụ dữ liệu: 100% qua Stored Procedure / Trigger / View / Function trên SQL Server (bao gồm `/health` và xác thực agent); không còn truy vấn `SELECT` trực tiếp trong backend.
- Next.js dashboard trong `web/`: BFF qua `/api/*`, hỗ trợ song ngữ **EN / VI**, đáp ứng 100% **Must + Should + Could + Design to Scale**.

```text
Next.js BFF (EN/VI + Mobile Web AR/QR) → Flask REST API → Stored Procedures → SQL Server
Python Collector (Batch + Offline Queue) ────────────────→ Flask REST API
```

## Các hạng mục đã hoàn thiện (tới 2026-11-19)

- **Lõi T-SQL & Bảo mật (`database/19_security_and_core_fixes.sql`)**:
  - `usp_health_check`, `usp_authenticate_collector_agent` (cập nhật `last_heartbeat_at`), `usp_record_telemetry` có nested-safe transaction và tự phục hồi trạng thái node (`ONLINE`/`WARNING`/`CRITICAL`/`UNAVAILABLE`) + auto-resolve `NODE_UNAVAILABLE`.
  - Trigger `trg_audit_logs_immutable` (`AFTER UPDATE, DELETE`, mã lỗi `51090`), `trg_ticket_status_audit` đọc `SESSION_CONTEXT(N'actor_user_id')`.
  - Database role quyền tối thiểu `db_ar_imms_executor` (`GRANT EXECUTE`, `DENY UPDATE, DELETE ON dbo.audit_logs`).
  - Covering index `IX_telemetry_node_metric_time_inc` tối ưu snapshot & lịch sử telemetry.
- **Mở rộng đầy đủ 25 bảng (`database/20_extended_features_procedures.sql`)**:
  - Seed dữ liệu cho `containers`, `asset_specs`, `asset_network_interfaces`, `warranty_info`, `maintenance_histories`, `notifications`.
  - Digital Twin 5 cấp, điều hướng 3-click sơ đồ Tủ Rack U-slot, quản lý hạ tầng `Site/Room/Rack` & cập nhật/di dời Node (`usp_list_racks`, `usp_list_sites_and_rooms`, `usp_manage_hierarchy`, `usp_update_node`, `usp_list_containers`, `usp_restart_container`, `usp_register_node`), tra cứu & quản lý AR/QR (`usp_lookup_node_by_marker`, `usp_manage_marker`).
  - Vòng đời Alert đầy đủ `OPEN → ACKNOWLEDGED → RESOLVED → CLOSED` (cả mức `WARNING` và `CRITICAL` trong `usp_record_telemetry`, `usp_update_alert_status`) + Chuông thông báo (`usp_list_notifications`, `usp_mark_notification_read`).
  - Quy trình Ticket đầy đủ cho cả `SYSTEM_OPERATOR` & `FIELD_TECHNICIAN` (`usp_assign_ticket`, `usp_list_ticket_notes`, `usp_add_ticket_note`, `usp_submit_ticket_closure_request`, `usp_review_ticket_closure_request`, `usp_update_ticket_status`).
  - Quản lý ngưỡng cảnh báo (`usp_list_alert_thresholds`, `usp_update_alert_threshold`), tài sản & bảo hành (`usp_list_assets`, `usp_upsert_asset_warranty`, `usp_list_maintenance_histories`), báo cáo PUE/Capacity/Trends & tổng hợp 4 cấp `Site/Room/Rack/Node` (`usp_get_analytics_summary`, `usp_get_capacity_report`, `usp_get_telemetry_history`, `usp_get_hierarchical_report`), và quản trị Admin + Collector Agents (`usp_list_users`, `usp_manage_user`, `usp_list_audit_logs`, `usp_list_assignable_technicians`, `usp_list_collector_agents`, `usp_manage_collector_agent`).
- **Real-time Streaming & Collector Container Sync**:
  - Backend Flask `GET /api/stream` (SSE `EventHub`) + Next.js BFF `web/app/api/stream/route.ts` giúp Dashboard tự cập nhật tức thì khi có telemetry/alert/ticket mới (kèm fallback polling 5s).
  - Collector `collector/agent.py` đồng bộ tự động cả telemetry hệ thống và Docker container stats (`POST /telemetry/containers`).
- **SQL Server Agent & Backup/Restore**:
  - Đã tạo và kích hoạt 5 job: `AR_IMMS_Check_Stale_Nodes`, `AR_IMMS_Job_Full_Backup`, `AR_IMMS_Job_Diff_Backup`, `AR_IMMS_Job_Log_Backup`, `AR_IMMS_Job_Cleanup_Old_Backups`.
  - Đã sửa lỗi `QUOTED_IDENTIFIER` cho `usp_check_stale_nodes` và `trg_alert_audit` tương thích filtered unique index `UX_alerts_one_open`; `database/11_test_heartbeat_job.sql` **PASS** (job chuyển node stale sang `UNAVAILABLE` sau ~9s, chỉ tạo đúng 1 alert chống trùng, `run_status = 1`).
  - Đã chạy kiểm chứng tạo Full/Diff/Log backup trong `backups/` và diễn tập khôi phục sang `AR_IMMS_RestoreTest` (`DBCC CHECKDB` sạch, `25/25` bảng).
- **Web Command Center & Mobile Web AR (`web/`)**:
  - Gỡ tiêu đề trang trí “Phân hệ/Modules” khỏi thanh điều hướng, giữ nguyên các mục phân hệ và nhãn truy cập.
  - BFF catch-all `web/app/api/[...path]/route.ts`, `POST /api/nodes` và `POST /api/telemetry/batch`.
  - Nút chuyển đổi ngôn ngữ **EN / VI** (`web/lib/i18n.ts`).
  - 5 phân hệ: **Overview & Digital Twin** (drill-down container, biểu đồ SVG lịch sử, onboard node cấp API key, ngưỡng cảnh báo, xác nhận cảnh báo, phân trang `25` mục/trang & luồng ticket Operator/Technician), **AR / QR Scanner** (`ArScannerTab` hỗ trợ camera/BarcodeDetector + preset marker testbed + HUD overlay), **Assets & Maintenance** (`AssetsTab`), **Analytics & PUE** (`AnalyticsTab` + xuất CSV UTF-8 BOM báo cáo 4 cấp), và **Admin & Audit** (`AdminTab` + phân trang `audit_logs` & xuất CSV UTF-8 BOM).
  - Tối ưu frontend chịu tải: tab-aware lazy polling (chỉ gọi API cần cho tab đang mở), SSE debounce `1500ms`, lưu phiên `sessionStorage` tự dọn khi 401/logout.
- **Scale Architecture, Columnstore & Least-Privilege (`database/22_scale_architecture.sql`, `23_least_privilege_login.sql`, `24_scale_benchmark_1m.sql`)**:
  - Bảng snapshot O(1) `dbo.node_latest_metrics` + cập nhật `dbo.vw_latest_telemetry` & `usp_record_telemetry`.
  - Partition `telemetry_metrics` theo tháng (`PF_TelemetryMonth`/`PS_TelemetryMonth`, PK `(id, timestamp)`, aligned indexes), bảng staging `dbo.telemetry_metrics_archive_staging` và `dbo.usp_purge_telemetry_partition` dùng `SWITCH PARTITION` tức thời.
  - Nonclustered Columnstore Index `NCCI_telemetry_analytics` phục vụ tổng hợp phân tích quy mô lớn.
  - `dbo.usp_record_telemetry_batch` (`OPENJSON`, rollback nguyên tử nếu có item sai, mã lỗi `51032`) nối với `POST /telemetry/batch` và collector `USE_BATCH=1`.
  - Bổ sung chỉ mục vận hành (`IX_agents_api_key_hash`, `IX_alerts_status_triggered`, `IX_tickets_status_created`, `IX_tickets_node_id`, `IX_notifications_user_read`) và phân trang `OFFSET...FETCH` + lọc tại SQL (`@node_id`, `@rack_id`) cho `usp_list_nodes_latest`, `usp_list_alerts`, `usp_list_tickets`, `usp_list_audit_logs`.
  - User quyền tối thiểu `ar_imms_app` thuộc role `db_ar_imms_executor` (`database/23_least_privilege_login.sql`).
- **Security Hardening, Session/MFA/Recovery & Bàn giao ca (`database/25_password_recovery.sql`, `26_security_hardening.sql`, `backend/security.py`, `docs/SECURITY-REVIEW.md`)**:
  - Quản lý phiên JWT có trạng thái (`auth_sessions`, `usp_validate_auth_session`, thu hồi phiên khác / đăng xuất fail-closed), trigger `trg_users_revoke_changed_credentials` tự tăng `security_version` khi đổi mật khẩu/role/trạng thái.
  - MFA TOTP + 10 backup codes cho `ADMINISTRATOR`, luồng yêu cầu cấp tài khoản & khôi phục mật khẩu 1 lần (`usp_request_account_access`, `usp_review_account_access_request`, `usp_issue_password_recovery`, `usp_redeem_password_recovery`), sổ bàn giao ca (`shift_handover_notes`).
  - Bảo vệ chống BOLA (`usp_authorize_ticket_write`, `usp_authorize_container_restart`), rate limiter `AttemptLimiter`, giới hạn kích thước JSON `1 MiB`, header `no-store`/`nosniff`, chống SSRF proxy & CSV Formula Injection.
  - Tự động đồng bộ mật khẩu dev qua `AR_IMMS_DEV_PASSWORD` trong `.env` (`sync_dev_passwords` khi `create_app()` khởi chạy, thay thế `scripts/set_dev_passwords.py`).

## Bằng chứng kiểm chứng (2026-11-19)

- **Compose smoke (`.\scripts\test-compose.ps1`)**: **PASS** (SQL Agent chạy, giới hạn RAM 3072 MB trong container 4 GiB, backup bind mount).
- **Backup/Restore & Agent Jobs**: **PASS** — cả 4 job backup (`Full`, `Diff`, `Log`, `Cleanup`) chạy thành công (`run_status = 1`), sinh `.bak`/`.trn` trong `backups/`; restore chuỗi `Full → Diff → Log` vào `AR_IMMS_RestoreTest` ở trạng thái `ONLINE`, `DBCC CHECKDB` 0 lỗi, `25/25` bảng khớp.
- **SQL Verification & Benchmark**:
  - `database/06_verify_seed_data.sql`: **PASS**.
  - `database/07_test_normalized_schema.sql`: **PASS** (3/3 ca kiểm thử).
  - `database/11_test_heartbeat_job.sql`: **PASS** (SQL Agent Job `AR_IMMS_Check_Stale_Nodes` đạt `run_status = 1`).
  - `database/18_test_retention_batch.sql`: **PASS** (`rows_deleted = 25000`, `remaining_rows = 0`).
  - `database/22_scale_architecture.sql`: **PASS** (idempotent qua 2 lần chạy liên tiếp; `usp_purge_telemetry_partition @partition_number = 2` thực thi `SWITCH PARTITION` sạch trong transaction rollback).
  - `database/23_least_privilege_login.sql`: **PASS** (`EXECUTE AS USER = N'ar_imms_app'` chạy thành công `usp_health_check` & `usp_list_nodes_latest`; bị từ chối `SELECT dbo.users` và `DELETE dbo.audit_logs` với lỗi SQL `229`).
  - `database/24_scale_benchmark_1m.sql` (**1,000,060 dòng** trải trên 4 partition tháng trong transaction rollback):
    - Đọc snapshot mới nhất: `[1A]` legacy `ROW_NUMBER` (Scan count 20, `4,747` logical reads, `9,456` read-ahead, `1,653 ms` CPU / `915 ms` elapsed) → `[1B]` O(1) `dbo.node_latest_metrics` (Scan count 1, **`2` logical reads** trên `node_latest_metrics` + `32` key-lookup reads trên `metric_types`, **`0 ms` CPU / `0 ms` elapsed**).
    - Tổng hợp toàn bảng: `[2A]` Rowstore (`4,747` logical reads, `269 ms` CPU / `70 ms` elapsed) → `[2B]` Columnstore `NCCI_telemetry_analytics` (`Segment reads 1`, `4,728` logical reads + `10` lob reads trong transaction chưa commit, **`131 ms` CPU** / `131 ms` elapsed).
    - Partition Pruning 1 tháng `[3]` (`250,000` dòng tháng `2026-10`): Scan count 1, **`1,186` logical reads**, `24 ms` CPU / `26 ms` elapsed.
- **Collector unit tests (`unittest discover -s collector/tests`)**: **6/6 PASS** trong `4.098s` (gồm test batch endpoint & fallback `404`).
- **Backend suite (`unittest discover -s backend -p "test_*.py" -v`)**: **52/52 PASS, 0 skipped** trong `4.745s` (gồm `test_auth_api.py`, `test_dashboard_api.py`, `test_telemetry_api.py`, `test_security_regressions.py`).
- **Frontend check & security tests (`cd web && npm test && npx tsc --noEmit`)**: **6/6 PASS** (chống SSRF proxy & CSV formula injection) + `tsc --noEmit` sạch (`0` lỗi).
- **Next.js build (`cd web && npm run build`)**: **PASS** (TypeScript strict `2.9s` + Turbopack build sạch, gồm route `/api/telemetry/batch`).

## Việc còn lại

- Thực hiện kiểm thử cài đặt trên máy thứ hai theo `docs/SETUP-WINDOWS.md` và ghi nhận kết quả tại mục 7 của tài liệu.
- Commit/push nhánh `dev-hoangminh-flask`, thực hiện kịch bản demo trên trình duyệt (`http://localhost:3000`) theo `docs/DEMO.md`, quay video và hoàn thiện báo cáo/slide vấn đáp.
