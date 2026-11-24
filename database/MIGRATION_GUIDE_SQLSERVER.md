# Chạy SQL Server

Hướng dẫn cài Docker, ODBC Driver 18, cấu hình `.env` và kiểm tra backend nằm tại
[docs/SETUP-WINDOWS.md](../docs/SETUP-WINDOWS.md). Cấu trúc database và lệnh cài đặt
chuẩn nằm tại [README.md](README.md).

## Cài đặt mới

Khởi động SQL Server Developer rồi chạy PowerShell tại thư mục gốc:

```powershell
docker compose up -d sqlserver
.\scripts\setup-database.ps1 -Database AR_IMMS -Server localhost,1433 -Credential (Get-Credential)
```

Runner chạy 19 script trong `database/canonical/` đúng thứ tự và dừng khi có lỗi.
Xem danh sách trước mà không thực thi SQL:

```powershell
.\scripts\setup-database.ps1 -DryRun
```

Không dùng runner để nâng cấp database đang có dữ liệu nếu chưa đánh giá tác động
của từng script. Các script gốc vẫn được lưu trong `database/legacy/`.

## Kiểm chứng

Chạy thủ công khi môi trường SQL Server đã sẵn sàng:

- `database/verification/tests/06_verify_seed_data.sql`
- `database/verification/tests/07_test_normalized_schema.sql`
- `database/verification/tests/11_test_heartbeat_job.sql`
- `database/verification/tests/18_test_retention_batch.sql`

Benchmark nằm trong `database/verification/benchmarks/`. Restore drill nằm trong
`database/verification/operations/15_restore_disaster_recovery.sql`. Reset dev
`database/verification/operations/00_reset.sql` có thể xóa dữ liệu; tuyệt đối
không chạy trên database đang sử dụng.

Sau khi khởi tạo database và đặt `AR_IMMS_DEV_PASSWORD` trong `.env`, Flask sẽ
đồng bộ mật khẩu placeholder của tài khoản demo qua stored procedure.

ERD và từ điển dữ liệu: [docs/ERD-DATA-DICTIONARY.md](../docs/ERD-DATA-DICTIONARY.md).
