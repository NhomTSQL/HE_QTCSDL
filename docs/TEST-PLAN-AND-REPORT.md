# Kế hoạch và báo cáo kiểm thử

## Nguyên tắc

Mỗi kết quả phải ghi lệnh/kịch bản, môi trường, ngày và PASS/FAIL/SKIPPED. Có code không đồng nghĩa đã kiểm chứng.

## Kiểm thử tự động

| Khu vực | Lệnh | Điều kiện |
|---|---|---|
| Backend | `py -m unittest discover -s backend/tests -t . -p "test_*.py" -v` | Python dependencies; một số test cần SQL Server/schema |
| Collector | `py -m unittest discover -s collector/tests -v` | Collector dependencies |
| Frontend tests | `cd web; npm test` | Node dependencies |
| TypeScript | `cd web; npx tsc --noEmit` | Node dependencies |
| Build | `cd web; npm run build` | Node dependencies và env phù hợp |

## Kiểm thử SQL Server

- `06_verify_seed_data.sql`: seed expected.
- `07_test_normalized_schema.sql`: ràng buộc/normalization.
- `11_test_heartbeat_job.sql`: stale-node và job result.
- `18_test_retention_batch.sql`: retention/batch rollback.
- `21_performance_benchmark.sql`: baseline query.
- `24_scale_benchmark_1m.sql`: scale/partition/columnstore; chạy riêng.
- `15_restore_disaster_recovery.sql`: restore vào DB thử nghiệm.

## Smoke checks

```powershell
.\scripts\test-health.ps1
.\scripts\test-compose.ps1
```

## Checklist regression

- health thành công khi SQL Server/schema sẵn sàng;
- login và session invalid/expired bị từ chối;
- collector thiếu/sai API key bị từ chối;
- telemetry invalid không gọi thành công procedure;
- batch quá giới hạn bị từ chối;
- role không đủ quyền không thực hiện được thao tác;
- audit không bị update/delete;
- API route và response contract không thay đổi;
- frontend không truy cập SQL Server trực tiếp.

## Báo cáo phiên hiện tại

Baseline trước đợt dọn tài liệu/backend: backend discovery được gọi nhưng môi trường chưa có database/schema sẵn sàng; log có cảnh báo bỏ qua dev password sync và lỗi authentication procedure. Vì vậy chưa ghi PASS cho backend integration, SQL Server verification, backup/restore hoặc frontend build khi chưa chạy lại lệnh trong môi trường đầy đủ.


