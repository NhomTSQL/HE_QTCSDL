# Trạng thái dự án AR-IMMS

Cập nhật: 2026-11-23. Nội dung trạng thái chỉ được xem là đã kiểm chứng khi có lệnh/kịch bản, môi trường và kết quả tương ứng. Tài liệu trạng thái này không thay thế log kiểm thử hoặc Jira acceptance evidence.

## Kiến trúc hiện tại

- Database chạy/nộp: SQL Server Developer.
- Backend/API: Flask; nghiệp vụ dữ liệu gọi Stored Procedure trên SQL Server. SQLAlchemy quản lý connection pool và thực thi procedure.
- Frontend: Next.js BFF/dashboard; không kết nối SQL Server trực tiếp.
- Collector: Python + psutil, gửi telemetry qua HTTP bằng API key.
- Luồng chính:

```text
Next.js BFF → Flask REST API → SQL Server Stored Procedures
Collector ──HTTP + X-API-Key──> Flask REST API
```

## Trạng thái theo bằng chứng

| Hạng mục | Trạng thái | Cách xác minh / ghi chú |
|---|---|---|
| Bộ script SQL Server, migration và schema | Đã có trong repo | Xem `database/README.md`, migration guide, ERD/data dictionary; chạy trên SQL Server theo hướng dẫn |
| Backup, restore, SQL Agent, partition/Columnstore | Có script và tài liệu kiểm chứng | Kết quả phụ thuộc đúng cấu hình SQL Server; không suy ra đã chạy thành công chỉ từ sự tồn tại của script |
| Backend unit tests | Có bộ test | Chạy `py -m unittest discover -s backend/tests -t . -p "test_*.py" -v`; kết quả gần nhất của phiên triển khai cần được ghi dưới đây |
| Collector tests | Có bộ test | Chạy `py -m unittest discover -s collector/tests -v` |
| Frontend tests/type/build | Có scripts npm | Chạy `npm test`, `npx tsc --noEmit`, `npm run build` trong `web/` |
| Cài đặt trên máy thứ hai | Chưa ghi nhận tại đây | Ghi lại máy/môi trường và `/health` khi kiểm chứng xong |
| Demo và báo cáo cuối kỳ | Còn cần hoàn thiện theo kế hoạch nhóm | Xem `docs/DEMO.md` và backlog |

## Kết quả chạy trong phiên cập nhật tài liệu

- Backend baseline: `py -m unittest discover -s backend/tests -t . -p "test_*.py"` — **chưa xác nhận PASS**. Có log cảnh báo bỏ qua đồng bộ mật khẩu vì database/schema không sẵn sàng và lỗi `usp_authenticate_user`; cần chạy lại khi SQL Server và schema đã khởi tạo.
- Không ghi PASS cho collector, frontend, SQL Agent, backup/restore hoặc benchmark nếu chưa chạy các lệnh tương ứng trong môi trường hiện tại.

## Cập nhật trạng thái

Khi hoàn tất một kiểm tra, ghi: ngày, commit/nhánh nếu hữu ích, lệnh hoặc kịch bản, môi trường (SQL Server/service/dependency), kết quả PASS/FAIL/SKIPPED và lỗi liên quan. Tách “đã có code” khỏi “đã kiểm chứng”.

