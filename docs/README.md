# Tài liệu AR-IMMS

Trang này là mục lục và xác định tài liệu chuẩn cho từng chủ đề. Backlog Jira
theo dõi công việc; tài liệu này mô tả phạm vi, quy ước và bằng chứng kỹ thuật.

## Cách chọn tài liệu

Xem [DOCUMENTATION-GUIDE.md](DOCUMENTATION-GUIDE.md) để tìm nhanh theo việc cần làm và hiểu file nào là nguồn chuẩn.

## Tài liệu chính

| Chủ đề | Tài liệu | Mục đích |
|---|---|---|
| Cài đặt nhanh | [README.md](../README.md) | Onboarding, khởi động các module và kiểm tra cơ bản |
| Cấu trúc mã nguồn | [ARCHITECTURE.md](ARCHITECTURE.md) | Backend `api/core/db/tests/tools`, collector và web |
| Kiến trúc | [ARCHITECTURE.md](ARCHITECTURE.md) | Các thành phần và luồng dữ liệu thực tế |
| Database | [DATABASE-SPECIFICATION.md](DATABASE-SPECIFICATION.md) và [README.md](../database/README.md) | Thiết kế dữ liệu, nhóm script và thứ tự triển khai |
| Vận hành | [OPERATION-GUIDE.md](OPERATION-GUIDE.md) | Backup/restore, SQL Agent, xử lý lỗi |
| Kiểm thử | [TEST-PLAN-AND-REPORT.md](TEST-PLAN-AND-REPORT.md) | Lệnh, tình huống và trạng thái bằng chứng |
| Hướng dẫn người dùng | [USER-MANUAL.md](USER-MANUAL.md) | Luồng sử dụng dashboard theo vai trò |
| Phạm vi và mức ưu tiên | [SCOPE-MOSCOW.md](SCOPE-MOSCOW.md) | Must/Should/Could/Won't; backlog không phải bằng chứng hoàn thành |
| Quy trình Kanban | [KANBAN-WORKFLOW.md](KANBAN-WORKFLOW.md) | Cột board, WIP, tiêu chí vào/ra |
| Quy ước kỹ thuật | [CONVENTIONS.md](CONVENTIONS.md) | Quy tắc SQL Server, T-SQL, backend và kiểm thử |
| Thiết kế dữ liệu | [ERD-DATA-DICTIONARY.md](ERD-DATA-DICTIONARY.md) | ERD, từ điển dữ liệu và chuẩn hóa |
| Cài đặt Windows | [SETUP-WINDOWS.md](SETUP-WINDOWS.md) | Cấu hình Windows/ODBC và kiểm tra đa máy |
| Trạng thái/bằng chứng | [STATUS.md](STATUS.md) | Phân biệt code đã có với kiểm thử đã xác minh |
| Hướng dẫn đọc tài liệu | [DOCUMENTATION-GUIDE.md](DOCUMENTATION-GUIDE.md) | Chọn tài liệu theo nhiệm vụ và nguồn sự thật |

## Tài liệu liên quan ngoài `docs/`

- [README.md](../README.md): hướng dẫn nhanh và liên kết chạy dự án.
- [README.md](../database/README.md): nhóm script database và lưu ý an toàn.
- [MIGRATION_GUIDE_SQLSERVER.md](../database/MIGRATION_GUIDE_SQLSERVER.md):
  thứ tự chạy, kiểm tra chạy lại và kiểm thử script SQL Server.
- Các script SQL nằm trong `database/`; script kiểm thử môi trường nằm trong
  `scripts/`.

## Quy tắc cập nhật

- Khi đổi phạm vi, cập nhật `SCOPE-MOSCOW.md` và các issue liên quan trước khi
  coi công việc là đã cam kết.
- Khi đổi cấu trúc board hoặc tiêu chí hoàn thành, cập nhật
  `KANBAN-WORKFLOW.md` và cấu hình Jira để hai nơi nhất quán.
- Khi đổi schema, cập nhật ERD/từ điển dữ liệu, script SQL và test tương ứng
  cùng một thay đổi.
- Ghi tại `STATUS.md` kết quả đã kiểm chứng; không suy ra trạng thái hoàn thành
  chỉ từ việc issue có trong backlog.
- Mọi khác biệt giữa tài liệu và mã nguồn/schema cần được nêu rõ và xử lý qua
  issue Jira; không âm thầm coi thiết kế dự kiến là hành vi đã triển khai.

`SPRINT-PLAN.md` không được duy trì: nhóm theo dõi công việc liên tục bằng
Kanban; các nhãn tuần trong backlog là mốc dự kiến, không phải sprint.

