# AR-IMMS — Đồ án môn Hệ quản trị CSDL

Hệ thống giám sát và bảo trì hạ tầng Data Center (Mini Data Center testbed).
Digital Twin: Site → Room → Rack → Node → Container.
Tài liệu: `docs/`. Hợp đồng API/SP: `docs/API.md`. Tiến độ: `docs/STATUS.md`.

## Ràng buộc của đề (bắt buộc)
- Database là **SQL Server** (Developer, chạy bằng Docker Compose). Không thay bằng DB khác.
- Deadline: đầu tháng 12/2026. Điểm môn nằm ở chiều sâu DB: ERD 3NF, T-SQL
  (SP/Function/View/Trigger), transaction, Index/Partition, phân quyền, Backup/Restore, Audit.
- Mọi thành viên phải giải thích được code mình làm (có vấn đáp).

## Stack (nhóm tự chọn)
- Web + API: **Next.js** (App Router, TypeScript), API trong `web/app/api/*`.
- Truy cập DB: gói **`mssql`** (tedious). Không ODBC, không ORM.
- Đăng nhập: JWT (`jose`) + `bcryptjs`.
- Collector: **Python 3 + psutil + requests**, thư mục `collector/`.
- Job định kỳ: SQL Server Agent job (stale node, retention).
- Realtime: polling 5 giây (Socket.IO/SSE chỉ làm nếu dư thời gian).

## Quy tắc nhóm (không phải luật của đề, nhưng giữ vì chấm điểm DB)
- Nghiệp vụ đi qua **stored procedure**. API route chỉ: validate đầu vào, xác thực/phân quyền,
  gọi SP, ánh xạ lỗi. Không viết SQL nghiệp vụ hay truy vấn ad hoc trong route.
- Ngưỡng cảnh báo đọc từ bảng `alert_thresholds`, không hard-code trong SP.
- Tên object: bảng/cột theo schema hiện có; SP `usp_`, function `ufn_`, view `vw_`, trigger `trg_`.
- Thời gian lưu UTC `datetime2`. Collector gửi `collected_at` dạng ISO-8601 UTC.
- Script DB đánh số trong `database/NN_*.sql`, chạy lại nhiều lần không lỗi, không xóa dữ liệu hợp lệ.
  Nhiều bước ghi dữ liệu: `SET XACT_ABORT ON`, `BEGIN TRY/CATCH`, rollback, `THROW` lỗi có nghĩa.
- Mỗi SP/trigger có chú thích mục đích + 1 test case (kịch bản, kết quả mong đợi, cách chạy).
- Không commit `.env`, mật khẩu, JWT secret, agent key, file `.bak`, `.venv`, `node_modules`.

## Phạm vi
Xem `docs/SCOPE-MOSCOW.md`. Đã cắt: AR thật/ArUco, mTLS, PUE, multi-site, hash-chain audit,
mobile native. "Mobile" = trang web responsive quét QR.

## Phân vùng thư mục (mỗi agent chỉ sửa vùng của mình)
| Vùng | Thư mục |
|---|---|
| DB | `database/` |
| Web + API | `web/` |
| Collector | `collector/` |
| Tài liệu / hợp đồng | `docs/` (chỉ người dùng hoặc agent được giao mới sửa `docs/API.md`) |

## Cách làm việc với Claude
- Trước thay đổi lớn: đưa kế hoạch ngắn (5-10 dòng) rồi làm.
- Commit nhỏ, thông điệp rõ. Không tự merge vào `main`.
- Cuối buổi: cập nhật `docs/STATUS.md` (làm gì, chạy lệnh nào để kiểm tra, còn thiếu gì).
