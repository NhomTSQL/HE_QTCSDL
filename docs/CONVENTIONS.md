# Quy ước kỹ thuật AR-IMMS

Quy ước này áp dụng cho thay đổi mới và tài liệu hóa. Nếu khác hiện trạng trong
repo, ghi rõ khác biệt và xử lý bằng issue/migration; không âm thầm đổi tên hoặc
di chuyển object trong một thay đổi không liên quan.

## CSDL và T-SQL

- CSDL triển khai là Microsoft SQL Server Developer. Script phải dùng T-SQL và
  được kiểm tra trên SQL Server, không dùng SQLite/PostgreSQL làm thay thế.
- Tên object mới theo PascalCase số ít cho bảng/thực thể; tên cột PascalCase
  theo convention đã chọn khi tạo schema. Không đổi tên object hiện hữu nếu chưa
  có phương án migration và cập nhật API/test/tài liệu tương ứng.
- Tên object lập trình dùng tiền tố thống nhất:
  - Stored procedure: `usp_`
  - User-defined function: `ufn_`
  - View: `vw_`
  - Trigger: `trg_`
- Trigger phải có phạm vi hẹp, xử lý nhiều dòng trong `inserted`/`deleted`, và
  không được gọi lại chính nó qua cập nhật gây recursion không kiểm soát.
- Dùng kiểu số có miền phù hợp; tránh `float` cho giá trị cần tính toán chính
  xác về tiền/định lượng. Mọi domain quan trọng nên được bảo vệ bởi
  `NOT NULL`, `CHECK`, `UNIQUE` và khóa ngoại phù hợp.
- Thời gian lưu theo UTC bằng `datetime2(0)`; giá trị mặc định tạo mới dùng
  `SYSUTCDATETIME()` nếu phù hợp nghiệp vụ. Tên cột phải thể hiện đúng nghĩa
  thời điểm. API chuyển đổi/định dạng UTC nhất quán.
- Procedure nhiều bước ghi dữ liệu phải xác định ranh giới transaction, xử lý
  lỗi bằng `TRY...CATCH`, rollback khi cần và trả lỗi có ý nghĩa; không nuốt lỗi
  hoặc trả thành công giả.
- Query báo cáo phải có điều kiện lọc và thứ tự ổn định khi phân trang. Index
  chỉ thêm khi có truy vấn mục tiêu và/hoặc số đo làm căn cứ.
- Mỗi procedure/trigger có chú thích ngắn về mục đích và ít nhất một test case:
  dữ liệu/kịch bản, kết quả mong đợi và cách chạy.

## Script database

- Chuẩn dự kiến cho script mới: thư mục `/db`, đánh số tăng dần
  `001_<purpose>.sql`, `002_<purpose>.sql`, ...; thiết lập mới chạy theo thứ tự.
- Repo hiện tại vẫn dùng `database/01_...sql` đến `database/07_...sql`.
  Không di chuyển hoặc đổi số loạt script hiện hữu trong thay đổi tài liệu này.
  Trước khi tạo script mới, nhóm cần quyết định qua Jira có chuyển toàn bộ sang
  `/db/001_...` hay tiếp tục loạt `database/08_...`; tránh duy trì hai chuỗi
  migration song song.
- Script thiết lập/schema/object nên chạy lại an toàn khi có thể; dùng
  `CREATE OR ALTER` cho procedure, function, view và trigger khi SQL Server
  mục tiêu hỗ trợ. Không xóa dữ liệu hợp lệ để đạt tính idempotent.
- Thay đổi schema cần có migration rõ ràng, xử lý dữ liệu cũ và rollback/fail
  fast phù hợp. Không coi `DROP`/reset toàn bộ DB là thao tác mặc định.
- Seed phải xác định, có thể chạy lại và không chứa mật khẩu thật. Hash mẫu
  hiện tại là placeholder, không dùng cho môi trường thực.
- Chạy verifier/test sau khi áp dụng script. Hướng dẫn hiện có ở
  [MIGRATION_GUIDE_SQLSERVER.md](../database/MIGRATION_GUIDE_SQLSERVER.md).

## Backend và hợp đồng API

- Backend Flask truy cập DB qua `pyodbc` và stored procedure; không đặt SQL
  nghiệp vụ, ORM hoặc truy vấn ad hoc trong route/service.
- API health/connectivity không được trở thành ngoại lệ âm thầm cho truy vấn
  nghiệp vụ. Hiện `backend/app.py` có `SELECT 1` để kiểm tra kết nối; cần phân
  biệt rõ đây là probe kỹ thuật và xử lý theo yêu cầu stored-procedure-only của
  dự án khi hoàn thiện backend.
- Giữ nguyên REST API contract của source tham chiếu trong phạm vi đã chọn.
  Thay đổi request/response/status code cần được nhóm chấp thuận và cập nhật
  test/tài liệu API.
- Validate dữ liệu ở biên API và kiểm tra lại invariant quan trọng trong DB;
  không dựa riêng vào frontend để bảo vệ dữ liệu.
- Lỗi DB phải được log/ánh xạ thành phản hồi API phù hợp; không trả thông tin
  bí mật, connection string, stack trace hoặc SQL nội bộ cho client.
- Không commit `.env`, mật khẩu, JWT secret, API key, credential collector hay
  dữ liệu backup chứa thông tin nhạy cảm.

## Quy ước frontend/collector và tích hợp

- Frontend gọi backend qua cấu hình API base; không kết nối trực tiếp SQL Server.
- Collector gửi telemetry theo contract backend; lỗi mạng phải có timeout,
  retry có giới hạn và không làm mất dữ liệu âm thầm khi có buffer.
- Timestamps giữa collector, API và DB thống nhất UTC; nêu đơn vị của metric
  rõ ràng.
- Socket.IO chỉ phát dữ liệu lấy từ luồng backend đã xác thực/kiểm soát quyền;
  không cho client ghi thẳng vào DB.
- QR chỉ dùng để mở luồng tra cứu web đã nằm trong scope; không diễn giải QR
  thành triển khai AR/ArUco.

## Tên và trạng thái hiện tại

Schema đang có trong repo dùng tên chữ thường dạng `snake_case` và một số
procedure/function tiền tố cũ như `sp_`/`fn_`; các script hiện nằm trong
`database/` với số `01`–`07`. Đây là hiện trạng cần được đối chiếu với chuẩn mục
tiêu PascalCase, tiền tố `usp_`/`ufn_` và loạt `/db/001_...` trong các issue
Jira trước khi chuyển đổi. Khi chuyển, phải làm trong thay đổi có kiểm thử và
cập nhật ERD/từ điển dữ liệu, backend và hướng dẫn chạy.
