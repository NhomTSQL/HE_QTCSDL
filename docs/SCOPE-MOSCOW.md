# Phạm vi AR-IMMS

## Mục tiêu

AR-IMMS là hệ thống giám sát và hỗ trợ bảo trì một testbed Data Center. Mô hình
hạ tầng số là `Site → Room → Rack → Node → Container`. Hệ thống thu thập
telemetry của Node, phát hiện cảnh báo, hỗ trợ xử lý ticket và trình bày dữ liệu
trên web.

Đây là đồ án môn Hệ quản trị CSDL: SQL Server là cơ sở dữ liệu triển khai và
chiều sâu thiết kế/vận hành CSDL là trọng tâm. Flask cung cấp REST API,
SQLAlchemy/pyodbc kết nối SQL Server, còn Python + psutil đảm nhiệm collector
phục vụ việc trình diễn luồng nghiệp vụ qua CSDL.

## Ràng buộc và cách đọc phạm vi

- Dùng SQL Server Developer cho bản nộp; không thay bằng PostgreSQL hoặc SQLite.
- Các thao tác nghiệp vụ của backend đi qua stored procedure trên SQL Server;
  không đưa truy vấn nghiệp vụ hoặc ORM trực tiếp vào backend.
- Giữ REST API contract của source mẫu trong phạm vi đã chọn; thay tầng dữ liệu
  phía sau theo thiết kế của nhóm.
- CSV Jira import là backlog và kế hoạch dự kiến. Một issue chỉ được coi là hoàn
  thành khi Jira và `STATUS.md` có trạng thái cùng bằng chứng kiểm thử/demo.
- Các tên Epic trong bảng dưới đây đối chiếu với bộ CSV Jira import hiện tại.
  Sau khi import, Jira là nơi theo dõi trạng thái; tài liệu này là nguồn mô tả
  phạm vi.

## MoSCoW

### Must — bắt buộc cho bản nộp

| Dòng công việc (Epic Jira) | Phạm vi |
|---|---|
| Môi trường & Repo | Môi trường chạy thống nhất, Docker Compose cho SQL Server, hướng dẫn cài đặt và kiểm tra trên máy nhóm; ghi nhận kết quả khảo sát source tham khảo |
| Schema SQL Server | ERD và từ điển dữ liệu; schema có ràng buộc; seed; script có thể chạy lại; chuẩn hóa và kiểm thử schema |
| Ingest & Collector | Collector thu thập và gửi telemetry; API ingest có xác thực agent; xử lý batch, lỗi và retry/buffer theo backlog |
| Alert & Ticket | Ngưỡng cảnh báo, chống tạo cảnh báo trùng, heartbeat/Node stale, quy trình tạo và xử lý ticket có trạng thái hợp lệ |
| Hiệu năng | Dữ liệu telemetry đủ lớn để đo; đánh giá truy vấn, execution plan, IO/thời gian; áp dụng và so sánh giải pháp index/partition/retention |
| Bảo mật & Audit | Đăng nhập JWT và phân quyền; SQL Login/User/Role và quyền tối thiểu; truyền ngữ cảnh người dùng nếu bật; audit thay đổi quan trọng |
| Backup/Restore | Kế hoạch Full/Differential/Log phù hợp môi trường, tự động hóa khả thi và kiểm chứng restore; giữ checklist/bằng chứng |
| Web & QR (Must) | Dashboard và cây Rack/Node; màn hình alert/ticket; đăng nhập và hiển thị chức năng theo role; cập nhật dữ liệu live qua SSE/polling |
| Báo cáo & Demo | Kiểm thử tích hợp đầu-cuối; báo cáo có bằng chứng về DB, hiệu năng, bảo mật, backup, kiến trúc/API và giao diện; kịch bản demo, phương án dự phòng và chuẩn bị vấn đáp |

Danh sách chi tiết, thứ tự và người phụ trách nằm trong backlog Jira. Không xem
các mục trong bảng là đã triển khai chỉ vì chúng được đánh dấu Must.

### Should — tính năng bổ sung trong phạm vi

Các mục dưới đây được mô tả là có trong source hiện tại; trạng thái nghiệm thu/bằng chứng theo từng hạng mục xem `docs/STATUS.md` và backlog Jira.

- Trang Mobile Web AR/QR Scanner (`ArScannerTab`) với camera/BarcodeDetector, HUD overlay thông số thời gian thực, container restart có audit và thao tác ticket tại hiện trường (`usp_lookup_node_by_marker`, `usp_manage_marker`).
- Báo cáo xu hướng telemetry theo Rack/Node (`usp_get_telemetry_history`) và phân tích năng lượng PUE / quy hoạch dung lượng (`usp_get_analytics_summary`, `usp_get_capacity_report`).
- View/SP dựng cây hạ tầng 5 cấp (`Site → Room → Rack → Node → Container`).
- Quản lý cấu hình phần cứng, NIC, lịch sử bảo trì và cảnh báo bảo hành sắp/đã hết hạn (`usp_list_assets`, `usp_upsert_asset_warranty`, `usp_list_maintenance_histories`).

### Could — mở rộng/Design to Scale

- **Nonclustered Columnstore Index `NCCI_telemetry_analytics`** (`database/migrations/22_scale_architecture.sql`) kết hợp Covering Index `IX_telemetry_node_metric_time_inc` tối ưu truy vấn phân tích/báo cáo quy mô lớn (giảm CPU/IO qua Columnstore Segment Reads).
- **Kiến trúc chịu tải & mở rộng (Design to Scale)**:
  - Bảng snapshot O(1) `dbo.node_latest_metrics` + cập nhật `dbo.vw_latest_telemetry` giúp đọc trạng thái mới nhất tức thời không cần quét bảng lịch sử.
  - Phân vùng bảng `telemetry_metrics` theo tháng (`PF_TelemetryMonth` / `PS_TelemetryMonth`) và lưu trữ/xóa tức thời bằng `SWITCH PARTITION` (`dbo.usp_purge_telemetry_partition`).
  - Batch telemetry ingest (`POST /telemetry/batch`, BFF `/api/telemetry/batch`, `usp_record_telemetry_batch` qua `OPENJSON`, collector `USE_BATCH=1` tự fallback `404/405`).
  - Phân trang phía server (`OFFSET...FETCH` với `limit/offset` và bộ lọc `node_id`/`rack_id` trên `usp_list_nodes_latest`, `usp_list_alerts`, `usp_list_tickets`, `usp_list_audit_logs`).
  - Tách tài khoản ứng dụng quyền tối thiểu `ar_imms_app` (`database/migrations/23_least_privilege_login.sql`) và benchmark quy mô lớn (`database/benchmarks/24_scale_benchmark_1m.sql`); số liệu benchmark chỉ có giá trị trong môi trường đã ghi nhận.
  - Tối ưu UI: tab-aware lazy polling, SSE debounce `1500ms`, lưu phiên làm việc `sessionStorage`, phân trang `25` mục/trang và xuất báo cáo CSV (UTF-8 BOM).

### Won't — ngoài phạm vi phiên bản này

- Ứng dụng mobile native React Native tách rời hoặc AR 3D SDK chuyên biệt; đã chọn Mobile Web AR/QR trực tiếp trên Next.js responsive.
- mTLS cho collector (đang dùng `X-API-Key` băm SHA-256).
- Vận hành nhiều site như một hệ thống multi-site phân tán hoàn chỉnh.
- Hash-chain audit (đang dùng trigger bất biến `trg_audit_logs_immutable` và `DENY UPDATE, DELETE` trên `audit_logs`).

Thay đổi mục Won't cần được nhóm thống nhất và cập nhật tài liệu cùng backlog
trước khi nhận việc.

## Mốc và nguyên tắc chốt

- Khung đồ án là 6 tuần; các nhãn W1–W5 trong CSV là mốc dự kiến cho luồng việc,
  không phải iteration/sprint.
- Must schema và phạm vi Must cần được rà soát, đóng băng vào cuối tuần 4.
  Sau mốc này, thay đổi schema phải nêu lý do, ảnh hưởng migration/test và được
  nhóm chấp thuận.
- Kanban cho phép kéo việc liên tục; mốc tuần là mốc theo dõi/kiểm tra, không
  tạo batch công việc bắt buộc.
- Source khóa trước chỉ là tham khảo. Thiết kế và triển khai tầng DB do nhóm
  thực hiện; không sao chép báo cáo/tài liệu hoặc thông tin cá nhân của nhóm khác.

## Tiêu chí nghiệm thu tổng thể

1. Cài mới theo [SETUP-WINDOWS.md](SETUP-WINDOWS.md) và tạo schema trên SQL
   Server thành công.
2. Script schema/seed/object có thể chạy lại theo hướng dẫn mà không phá dữ liệu
   hợp lệ; các script verifier và test có kết quả mong đợi.
3. Luồng Must được demo đầu-cuối bằng dữ liệu kiểm thử và có kiểm tra lỗi/biên
   quan trọng, không chỉ trình bày giao diện tĩnh.
4. Các kết luận hiệu năng dựa trên phép đo trước/sau và truy vấn được nêu rõ;
   không báo cáo chỉ số chưa đo.
5. Backup được xác minh và ít nhất một lần restore được thực hiện, ghi lại kết
   quả, giới hạn và checklist.
6. Thành viên có thể giải thích phần việc của mình và các quyết định DB liên quan.

