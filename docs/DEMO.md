# Kịch bản demo AR-IMMS

Mục tiêu: chứng minh luồng `collector → Flask API → SQL Server`.

## Chuẩn bị

- SQL Server Docker đang ở trạng thái `healthy`.
- Đã chạy schema, seed và `database/08_dev_node_api_key.sql`.
- Đã cài dependency trong `backend/requirements.txt`.
- Có `.env` cục bộ với `DATABASE_URL`.

## Bước 1: Khởi động Flask

```powershell
.\.venv\Scripts\python.exe backend/app.py
```

Kiểm tra health:

```powershell
Invoke-RestMethod http://localhost:5000/health
```

Kết quả mong đợi:

```json
{"status":"healthy","database":"connected"}
```

## Bước 2: Gửi telemetry hợp lệ

```powershell
$body = @{
  metric_type = "cpu_usage_percent"
  value = 42.5
  unit = "%"
} | ConvertTo-Json

Invoke-RestMethod `
  -Method Post `
  -Uri http://localhost:5000/telemetry `
  -Headers @{ "X-API-Key" = "demo-node-key-001" } `
  -ContentType "application/json" `
  -Body $body
```

Kết quả mong đợi là HTTP `201` với `status=recorded`.

## Bước 3: Kiểm tra lỗi và transaction

- Không có `X-API-Key` hoặc key sai: HTTP `401`.
- Body không phải JSON object hoặc thiếu trường: HTTP `400`.
- `node_id` không khớp agent: HTTP `403`.
- Metric/unit không hợp lệ: HTTP `422`.
- Kiểm tra `telemetry_metrics` để xác nhận request lỗi không tạo thêm dòng.

## Bước 4: Chạy test tự động

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s backend -p "test_*.py" -v
.\.venv\Scripts\python.exe -m unittest discover -s collector/tests -v
Set-Location web; npm test; npx tsc --noEmit
```

Backend đạt **52/52 PASS** (nhờ `AR_IMMS_DEV_PASSWORD` trong `.env` tự đồng bộ cho 3 tài khoản mẫu), collector **6/6 PASS**, frontend security/CSV **6/6 PASS**.

## Bước 5: Demo Full-Stack trên Web Dashboard (`http://localhost:3000`)

1. Khởi động backend (`py backend/app.py`), collector (`py collector/agent.py`) và frontend (`cd web && npm run dev`).
2. Đăng nhập lần lượt bằng `admin`, `operator`, `technician` (mật khẩu là giá trị `AR_IMMS_DEV_PASSWORD` trong `.env`), trình diễn chuyển đổi ngôn ngữ **EN / VI** và danh mục phân hệ trên cả desktop lẫn mobile drawer.
3. **Tổng quan & Digital Twin**: Duyệt cây 5 cấp (`Site → Room → Rack → Node → Container`), xem cập nhật real-time qua SSE, cấu hình ngưỡng cảnh báo, xác nhận cảnh báo và tạo ticket.
4. **Việc của tôi & Bàn giao ca**: Đăng nhập `technician` để nhận việc, thêm ghi chú bàn giao ca (`shift_handover_notes`), gửi yêu cầu đóng ticket (`PENDING_CLOSURE`), sau đó dùng `operator`/`admin` duyệt đóng (`CLOSED`) và kiểm tra ghi nhận lịch sử bảo trì.
5. **Quét AR / QR**: Chọn hoặc quét marker testbed, xem HUD thông số trực tiếp và khởi động lại container có kiểm tra quyền BOLA (`usp_authorize_container_restart`).
6. **Tài sản & Bảo trì / Báo cáo & PUE**: Kiểm tra hạn bảo hành, phân tích PUE, capacity theo Rack và xuất file CSV UTF-8 BOM.
7. **Quản trị & Audit**: Xem nhật ký bất biến (`audit_logs`), thử sửa/xóa trực tiếp trong SSMS để chứng minh trigger `trg_audit_logs_immutable` chặn với mã lỗi `51090`; trình diễn quản lý phiên đăng nhập và MFA TOTP.

## Checklist câu hỏi vấn đáp CSDL (SSMS)

- **Kiến trúc SP & Bảo mật**: `usp_validate_auth_session`, `trg_users_revoke_changed_credentials`, `SESSION_CONTEXT(N'actor_user_id')`, user quyền tối thiểu `ar_imms_app` (`23_least_privilege_login.sql`).
- **Hiệu năng & Scale**: Chạy `24_scale_benchmark_1m.sql` so sánh `ROW_NUMBER` với bảng snapshot O(1) `node_latest_metrics`, Columnstore Index `NCCI_telemetry_analytics`, Partition Pruning và `SWITCH PARTITION`.
- **An toàn dữ liệu**: Kiểm tra `msdb.dbo.sysjobhistory` cho 5 SQL Agent Jobs và kết quả khôi phục `AR_IMMS_RestoreTest` (`15_restore_disaster_recovery.sql`).

### Bộ truy vấn trình diễn nhanh trong SSMS khi vấn đáp

```sql
-- 1. Kiểm chứng 32 bảng & phân vùng trên telemetry_metrics + Columnstore Index
USE AR_IMMS;
SELECT COUNT(*) AS total_tables FROM sys.tables;
SELECT p.partition_number, p.rows
FROM sys.partitions p
WHERE p.object_id = OBJECT_ID(N'dbo.telemetry_metrics') AND p.index_id IN (0, 1)
ORDER BY p.partition_number;
SELECT name, type_desc FROM sys.indexes
WHERE object_id = OBJECT_ID(N'dbo.telemetry_metrics') AND name = N'NCCI_telemetry_analytics';

-- 2. So sánh IO/Time giữa ROW_NUMBER truyền thống và snapshot O(1) node_latest_metrics
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
;WITH cte AS (
    SELECT node_id, metric_type_id, value, timestamp,
           ROW_NUMBER() OVER (PARTITION BY node_id, metric_type_id ORDER BY timestamp DESC, id DESC) AS rn
    FROM dbo.telemetry_metrics
)
SELECT node_id, metric_type_id, value, timestamp FROM cte WHERE rn = 1;

SELECT node_id, metric_type_id, value, timestamp FROM dbo.node_latest_metrics;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- 3. Kiểm chứng phân quyền tối thiểu (EXECUTE-only, bị chặn đọc bảng nhạy cảm)
EXECUTE AS USER = N'ar_imms_app';
EXEC dbo.usp_list_nodes_latest;
-- Câu sau phải báo lỗi SQL 229 (SELECT permission denied):
SELECT TOP (1) id, username FROM dbo.users;
REVERT;

-- 4. Kiểm chứng tính bất biến của audit_logs (trigger trg_audit_logs_immutable báo lỗi 51090)
DELETE FROM dbo.audit_logs WHERE id = 1;

-- 5. Kiểm chứng lịch sử chạy 5 SQL Server Agent Jobs
SELECT TOP (20) j.name, h.step_name, h.run_status, h.run_date, h.run_time
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.name LIKE N'AR_IMMS_%' AND h.step_id = 0
ORDER BY h.instance_id DESC;
```

## Phương án dự phòng

- Nếu collector không chạy, gửi request bằng PowerShell như bước 2.
- Nếu SQL Server chưa healthy, kiểm tra `docker compose ps` và log container.
