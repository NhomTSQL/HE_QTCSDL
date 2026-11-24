# AR-IMMS — Quy tắc phát triển

AR-IMMS là hệ thống giám sát và bảo trì hạ tầng Data Center thử nghiệm. Mô hình Digital Twin là `Site → Room → Rack → Node → Container`.

## 1. Ràng buộc bắt buộc

- Database triển khai và bản nộp là **Microsoft SQL Server Developer**. Không thay bằng PostgreSQL hoặc SQLite.
- Backend chỉ thực hiện nghiệp vụ dữ liệu thông qua Stored Procedure trên SQL Server. SQLAlchemy/pyodbc chỉ dùng làm lớp kết nối, transaction và thực thi procedure; không dùng ORM query cho nghiệp vụ.
- Không kết nối SQL Server trực tiếp từ Next.js hoặc collector.
- Giữ nguyên REST API contract, tên procedure, schema và response hiện có nếu thay đổi chưa được nhóm duyệt.
- Không commit `.env`, mật khẩu, JWT secret, API key, khóa MFA hoặc file backup chứa dữ liệu thật.

## 2. Kiến trúc

```text
Next.js BFF / UI ──HTTP──> Flask REST API ──stored procedures──> SQL Server
Python collector ────────HTTP + X-API-Key──> Flask REST API
```

- `backend/`: Flask API, xác thực, security headers và gọi procedure.
- `collector/`: thu thập telemetry bằng `psutil`, buffer/retry và gửi HTTP.
- `web/`: Next.js dashboard/BFF; không chứa logic truy cập SQL Server.
- `database/`: T-SQL triển khai, kiểm chứng, backup/restore và benchmark.
- `docs/`: kiến trúc, vận hành, database, test và hướng dẫn người dùng.

## 3. Quy tắc database

- Script mới dùng T-SQL, UTC `datetime2(0)` và tiền tố `usp_`, `ufn_`, `vw_`, `trg_`.
- Không đổi tên hoặc xóa object hiện hữu nếu chưa có migration, test và cập nhật tài liệu.
- Procedure ghi dữ liệu phải có transaction boundary, `TRY...CATCH`, rollback phù hợp và lỗi có ý nghĩa.
- Trigger phải xử lý nhiều dòng trong `inserted`/`deleted` và không gây recursion ngoài kiểm soát.
- Script seed không chứa mật khẩu thật. Hash trong seed chỉ là placeholder.
- Không chạy `database/verification/operations/00_reset.sql` trên database đang sử dụng.
- Thứ tự chạy chuẩn nằm tại [database/README.md](database/README.md) và [database/MIGRATION_GUIDE_SQLSERVER.md](database/MIGRATION_GUIDE_SQLSERVER.md). Không tạo chuỗi migration song song.

## 4. Quy tắc backend/API

- Validate dữ liệu tại biên API; invariant quan trọng vẫn phải được bảo vệ trong database.
- Lỗi procedure phải rollback và ánh xạ thành status/message API phù hợp; không trả SQL, connection string hoặc stack trace cho client.
- Route không chứa query nghiệp vụ ad hoc. Khi cần thêm nghiệp vụ, ưu tiên thêm procedure/test trước rồi gọi từ backend.
- Không thay đổi request, response hoặc status code chỉ để làm code “đẹp hơn”.
- Mỗi thay đổi non-trivial cần một test có thể chạy lại; test phải bao phủ cả lỗi và đường thành công.

## 5. Quy tắc frontend/collector

- Frontend gọi Flask qua API base/BFF; không kết nối database.
- Collector phải có timeout, retry giới hạn và không làm mất dữ liệu âm thầm khi có buffer.
- Timestamp giữa collector, API và DB dùng UTC; metric phải có unit rõ ràng.
- Không gọi QR/marker là AR 3D native: phạm vi hiện tại là Mobile Web AR/QR.

## 6. Quy trình thay đổi

1. Đọc tài liệu liên quan và kiểm tra trạng thái hiện tại.
2. Với thay đổi lớn, viết kế hoạch ngắn trước khi sửa.
3. Thay đổi nhỏ, tập trung; không refactor lan sang API/database nếu không cần.
4. Chạy test liên quan, sau đó chạy bộ kiểm tra tổng thể có thể chạy trong môi trường hiện tại.
5. Cập nhật `docs/STATUS.md` chỉ với kết quả có lệnh, ngày và môi trường kiểm chứng.
6. Trước khi bàn giao, chạy `git diff --check` và kiểm tra secret/path/API contract.

## 7. Không thuộc phạm vi hiện tại

- PostgreSQL/Supabase, SQLite thay thế SQL Server.
- React Native hoặc AR 3D native tách rời.
- mTLS collector, multi-site phân tán và hash-chain audit.

