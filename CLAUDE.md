# AR-IMMS — Đồ án môn Hệ quản trị CSDL

Hệ thống giám sát và bảo trì hạ tầng Data Center (Mini Data Center testbed). Digital Twin: Site → Room → Rack → Node → Container. Tài liệu chi tiết nằm trong `docs/`.

## Ràng buộc cứng (không được vi phạm)
- Database BẮT BUỘC là **SQL Server** (Developer).
- Trọng tâm ở chiều sâu DB: ERD 3NF, T-SQL (SP/Function/View/Trigger), transaction, Index/Partition, phân quyền, Backup/Restore, Audit.
- Backend chỉ truy cập DB qua **Stored Procedure** (pyodbc). Không rải query/ORM trong code.

## Stack
Flask (backend) · Next.js (web) · Python + psutil (collector) · SQL Server Developer · Socket.IO · JWT.

## Phạm vi
Xem `docs/SCOPE-MOSCOW.md`. Đã cắt: AR thật/ArUco, mTLS, PUE, multi-site, hash-chain audit, mobile native. Mobile = web quét QR.

## Quy ước
Xem `docs/CONVENTIONS.md` (PascalCase số ít, `usp_/ufn_/vw_/trg_`, UTC `datetime2(0)`). Script DB đánh số trong `/db`: `001_...sql`, chạy lại được từ đầu.

## Tài liệu và luồng công việc
Mục lục tài liệu tại `docs/README.md`. Nhóm làm theo Kanban, không chia sprint; xem `docs/KANBAN-WORKFLOW.md`. Khung đồ án 6 tuần, đóng băng phạm vi và schema Must ở cuối W4 theo `docs/SCOPE-MOSCOW.md`. Tiến độ đã kiểm chứng ở `docs/STATUS.md`.

## Cách làm việc với Claude
- Trước thay đổi lớn: đưa kế hoạch ngắn để nhóm duyệt.
- Giải thích ngắn lý do mỗi đoạn T-SQL để học được và trả lời.
- Mỗi SP/trigger kèm chú thích và 1 test case (kịch bản + kết quả mong đợi).
- Không commit mật khẩu, khóa bí mật, file `.env`.
- Cuối buổi: cập nhật `docs/STATUS.md`.
