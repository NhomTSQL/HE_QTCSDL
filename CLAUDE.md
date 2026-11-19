# AR-IMMS — Đồ án môn Hệ quản trị CSDL

Hệ thống giám sát và bảo trì hạ tầng Data Center (Mini Data Center testbed). Digital Twin: Site → Room → Rack → Node → Container. Tài liệu chi tiết nằm trong `docs/`.

## Ràng buộc cứng (không được vi phạm)
- Database BẮT BUỘC là **SQL Server** (Developer). Không dùng PostgreSQL/SQLite cho bản nộp.
- Điểm môn nằm ở chiều sâu DB: ERD 3NF, T-SQL (SP/Function/View/Trigger), transaction, Index/Partition, phân quyền, Backup/Restore, Audit.
- Backend chỉ truy cập DB qua **Stored Procedure** (pyodbc). Không rải query/ORM trong code.
- Giữ nguyên REST API contract của source mẫu; chỉ thay tầng dữ liệu phía sau.
- Nhóm 5 sinh viên, 6 tuần. Mọi thành viên phải giải thích được code mình làm (có vấn đáp).
- Source khóa trước chỉ là **tham chiếu**. Thiết kế và code tầng DB do nhóm tự làm. Không copy tài liệu/báo cáo của họ, không đưa tên/MSSV người khác vào repo.

## Stack
Flask (backend) · Next.js (web + Mobile Web AR/QR) · Python + psutil (collector) · SQL Server Developer · JWT · Song ngữ EN/VI.

## Phạm vi
Xem `docs/SCOPE-MOSCOW.md`. Đã triển khai đầy đủ theo đề cương: Digital Twin 5 cấp (`Site → Room → Rack → Node → Container`), Mobile Web AR/QR Scanner với HUD overlay, PUE & Capacity Analytics, quản lý Tài sản & Bảo hành, Admin & Immutable Audit. Đã cắt: ứng dụng React Native/AR 3D tách rời, mTLS, multi-site, hash-chain audit.

## Quy ước
Xem `docs/CONVENTIONS.md` (PascalCase số ít, `usp_/ufn_/vw_/trg_`, UTC `datetime2(0)`). Script DB đánh số trong `database/`: `01_...sql` đến `21_...sql`, chạy lại được từ đầu.

## Lộ trình
6 tuần, đóng băng phạm vi và schema Must ở cuối W4. Nhóm theo dõi công việc bằng Kanban, xem `docs/KANBAN-WORKFLOW.md`; tiến độ hiện tại ở `docs/STATUS.md`.

## Cách làm việc với Claude
- Trước thay đổi lớn: đưa kế hoạch ngắn để nhóm duyệt.
- Giải thích ngắn lý do mỗi đoạn T-SQL để sinh viên học được và trả lời vấn đáp.
- Mỗi SP/trigger kèm chú thích và 1 test case (kịch bản + kết quả mong đợi).
- Không commit mật khẩu, khóa bí mật, file `.env`.
- Cuối buổi: cập nhật `docs/STATUS.md`.
