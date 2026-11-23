# Hướng dẫn vận hành

## Khởi động

1. Khởi động Docker Desktop.
2. Chạy `docker compose up -d sqlserver`.
3. Xác nhận `docker compose ps` báo healthy.
4. Kiểm tra `.env` cục bộ và ODBC Driver 18.
5. Chạy migration theo [database/README.md](../database/README.md).
6. Khởi động Flask, sau đó web và collector.
7. Gọi `/health` trước khi demo.

## Backup và restore

Các script `12`–`15` cấu hình recovery model, SQL Agent backup/cleanup và restore drill. Chỉ chạy job/restore theo đúng hướng dẫn trong script và [BACKUP-TEST-CASES.md](BACKUP-TEST-CASES.md).

Quy tắc:

- Backup phải lưu ngoài container qua bind mount khi chạy local.
- Không commit `.bak`, `.trn` hoặc dữ liệu backup thật.
- Restore vào database thử nghiệm riêng, không ghi đè database đang dùng.
- Sau restore chạy `DBCC CHECKDB` và đối chiếu bảng/kết quả mong đợi.

## SQL Server Agent

Heartbeat và backup jobs cần SQL Server Agent hoạt động trong container. Khi job không chạy:

1. kiểm tra container/service;
2. kiểm tra job/schedule trong `msdb`;
3. đọc job history và lỗi SQL;
4. không đánh dấu PASS nếu chỉ thấy job tồn tại mà chưa có `run_status = 1`.

## Xử lý lỗi ứng dụng

- `503` khi health fail: kiểm tra SQL Server, `DATABASE_URL`, ODBC driver và schema.
- `401`: kiểm tra JWT/session hoặc `X-API-Key`.
- `422/4xx` từ telemetry: kiểm tra metric type, unit, node binding và batch size.
- Lỗi procedure: giữ mã lỗi/log server, rollback transaction và sửa nguyên nhân; không bỏ qua để chạy tiếp migration.

## Dừng hệ thống

```powershell
# Dừng web/backend/collector bằng Ctrl+C trong từng terminal
docker compose stop sqlserver
```

Không dùng `docker compose down -v` nếu cần giữ volume/database local.


