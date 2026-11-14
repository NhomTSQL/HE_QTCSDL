# Trạng thái dự án

## Database scripts

- Schema SQL Server có ERD/từ điển dữ liệu và phân tích 3NF tại `docs/ERD-DATA-DICTIONARY.md`.
- `database/02_create_tables.sql` tạo 25 bảng; schema tách RBAC, metric/unit, marker coordinates và NIC thành các quan hệ riêng.
- Khi nâng cấp schema cũ, script chuyển JSON/chuỗi trong transaction; dữ liệu không ánh xạ được gây lỗi và rollback thay vì bị bỏ âm thầm.
- Script schema, index và database object hỗ trợ chạy lại; seed data thêm các hàng còn thiếu.
- `database/06_verify_seed_data.sql` kiểm tra seed/schema; `database/07_test_normalized_schema.sql` kiểm tra SP với dữ liệu hợp lệ, đơn vị sai và metric không tồn tại.
- Các hash mật khẩu trong seed data chỉ là placeholder; phải thay bằng hash hợp lệ trước khi dùng đăng nhập.
- - `database/12_backup_recovery_model.sql`–`15_restore_disaster_recovery.sql`: chuyển recovery model FULL, SQL Agent job Full (CN 00:00), Diff (T2–T7 23:00), Log (30 phút) kèm `CHECKSUM` + `RESTORE VERIFYONLY`, job dọn file cũ hơn 7 ngày và script restore Full → Diff → Log.

## Kiểm tra và review

- SQL Server Express: thiết lập mới chạy script 01–05 hai lượt, sau đó `06` và `07` đều PASS.
- SQL Server Express: tạo schema cũ từ commit trước, chạy nâng cấp 02 và seed/object mới hai lượt; dữ liệu quyền, tọa độ, metric và NIC được giữ lại; `06`/`07` đều PASS.
- Hướng dẫn cài đồng nhất cho Windows, Docker, ODBC Driver 18, `.env`, URL-encode và kiểm tra `/health` trên hai máy: `docs/SETUP-WINDOWS.md`.
- Script smoke test endpoint: `scripts/test-health.ps1`.
- Compose bật SQL Server Agent, mount `backups/` vào container và giới hạn memory; `scripts/test-compose.ps1` kiểm tra Agent, backup/verify, host mount và hard limit.
- Docker Compose smoke test đã chạy thành công hai lần với container SQL Server: Agent `Running`, SQL Server thấy giới hạn 3072 MB, container giới hạn 4 GiB, backup được verify và file hiện trên host.
- Sau khi recreate container, database `AR_IMMS` vẫn còn; Flask `/health` kết nối Docker SQL Server thực tế và trả `healthy`.
- Đã kiểm tra cú pháp PowerShell, lỗi kết nối trả 503 qua Flask test client, và URL-encode password có ký tự đặc biệt.
- Review PR và chạy thử trên máy thứ hai còn chờ nhóm xác nhận.
- Load test ingest (`backend/load_test_ingest.py`): gửi `POST /telemetry` ở 3 mức 10/30/50 req/s (2300 request) tới Flask (debug tắt) và SQL Server Developer trên Windows, laptop 4 GB RAM. Kết quả: 2300/2300 phản hồi 201, 0 lỗi, tốc độ ghi thực tế 10/30/50 req/s, p95 lần lượt 59,1/30,5/29,8 ms. Đối chiếu DB: số dòng `telemetry_metrics` tăng đúng <số dòng tăng> dòng, `alerts` và trạng thái node không đổi. Test case và cách chạy lại: `docs/LOAD-TEST-INGEST.md`.
- Load test ingest chưa chạy trên Docker và chưa xác định ngưỡng tối đa; đo bằng `127.0.0.1` vì lần đo đầu bằng `localhost` cho độ trễ khoảng 2 giây (nghi do IPv6, chưa kiểm chứng).

## Tài liệu và quản lý công việc

- Đã có mục lục tài liệu, phạm vi MoSCoW, quy ước kỹ thuật và hướng dẫn luồng
  Kanban tại `docs/README.md`, `docs/SCOPE-MOSCOW.md`,
  `docs/CONVENTIONS.md` và `docs/KANBAN-WORKFLOW.md`.
- Backlog Jira CSV là kế hoạch dự kiến, không phải bằng chứng các Epic đã hoàn
  thành. Cần xác nhận cấu hình board/WIP, mapping các cột `Labels` khi import
  và phân công người thứ năm (CSV hiện có vai A–D).
- Task khảo sát/chạy thử source tham khảo và ghi `SOURCE-AUDIT` trong backlog
  chưa có kết quả được xác minh trong repo này; cần hoàn thành riêng trước khi
  đánh dấu issue tương ứng là Done.
- Cần nhóm rà soát WIP/DoR/DoD đề xuất và đối chiếu quy ước mục tiêu với hiện
  trạng schema/script cũ trước khi áp dụng migration đổi tên/di chuyển script.
