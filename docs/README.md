# Tài liệu AR-IMMS

Trang này là mục lục và xác định tài liệu chuẩn cho từng chủ đề.

## Tài liệu chính

| Chủ đề | Tài liệu | Nguồn chuẩn |
|---|---|---|
| Phạm vi và mức ưu tiên | [SCOPE-MOSCOW.md](SCOPE-MOSCOW.md) | Must/Should/Could/Won't |
| Hợp đồng API và SP | [API.md](API.md) | Endpoint REST + chữ ký SP đóng băng |
| Kế hoạch sprint | [SPRINT-PLAN.md](SPRINT-PLAN.md) | Lịch 11/11 → 02/12, phân công agent |
| Kịch bản demo | [DEMO.md](DEMO.md) | Demo 5 phút end-to-end |
| Quy ước kỹ thuật | [CONVENTIONS.md](CONVENTIONS.md) | SQL Server, T-SQL, backend |
| Thiết kế dữ liệu | [ERD-DATA-DICTIONARY.md](ERD-DATA-DICTIONARY.md) | ERD, từ điển dữ liệu, 3NF |
| Cài đặt Windows | [SETUP-WINDOWS.md](SETUP-WINDOWS.md) | Môi trường, cấu hình |
| Tiến độ và bằng chứng | [STATUS.md](STATUS.md) | Trạng thái xác minh, việc còn lại |

## Tài liệu liên quan ngoài `docs/`

- [README.md](../README.md): hướng dẫn nhanh.
- [MIGRATION_GUIDE_SQLSERVER.md](../database/MIGRATION_GUIDE_SQLSERVER.md):
  thứ tự chạy script SQL Server.

## Quy tắc cập nhật

- Khi đổi phạm vi: cập nhật `SCOPE-MOSCOW.md` trước.
- Khi đổi schema: cập nhật ERD/từ điển dữ liệu cùng lúc.
- Khi đổi API: phải được người dùng duyệt, cập nhật `API.md`.
- Ghi kết quả xác minh vào `STATUS.md`; không suy ra trạng thái từ backlog.
