# Tài liệu AR-IMMS

Trang này là mục lục và xác định tài liệu chuẩn cho từng chủ đề. Backlog Jira
theo dõi công việc; tài liệu này mô tả phạm vi, quy ước và bằng chứng kỹ thuật.

## Tài liệu chính

| Chủ đề | Tài liệu | Nguồn chuẩn |
|---|---|---|
| Phạm vi và mức ưu tiên | [SCOPE-MOSCOW.md](SCOPE-MOSCOW.md) | Phạm vi Must/Should/Could/Won't; CSV Jira là backlog dự kiến, không phải bằng chứng hoàn thành |
| Quy trình Kanban | [KANBAN-WORKFLOW.md](KANBAN-WORKFLOW.md) | Cột board, WIP, tiêu chí vào/ra và nhịp rà soát |
| Quy ước kỹ thuật | [CONVENTIONS.md](CONVENTIONS.md) | Quy tắc SQL Server, T-SQL, backend và kiểm thử |
| Thiết kế dữ liệu | [ERD-DATA-DICTIONARY.md](ERD-DATA-DICTIONARY.md) | ERD, từ điển dữ liệu và phân tích chuẩn hóa |
| Cài đặt Windows | [SETUP-WINDOWS.md](SETUP-WINDOWS.md) | Môi trường, cấu hình cục bộ và chạy ứng dụng |
| Tiến độ và bằng chứng | [STATUS.md](STATUS.md) | Trạng thái đã xác minh, việc còn lại và kết quả kiểm thử |

## Tài liệu liên quan ngoài `docs/`

- [README.md](../README.md): hướng dẫn nhanh và liên kết chạy dự án.
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
