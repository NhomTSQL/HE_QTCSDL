# Phạm vi AR-IMMS

## Mục tiêu

AR-IMMS là hệ thống giám sát và hỗ trợ bảo trì một testbed Data Center. Mô hình
hạ tầng số là `Site → Room → Rack → Node → Container`. Hệ thống thu thập
telemetry của Node, phát hiện cảnh báo, hỗ trợ xử lý ticket và trình bày dữ liệu
trên web.

Đây là đồ án môn Hệ quản trị CSDL: SQL Server là cơ sở dữ liệu triển khai và
chiều sâu thiết kế/vận hành CSDL là trọng tâm. Backend Flask, web Next.js và
collector phục vụ việc trình diễn luồng nghiệp vụ qua CSDL.

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
| Web & QR (Must) | Dashboard và cây Rack/Node; màn hình alert/ticket; đăng nhập và hiển thị chức năng theo role; cập nhật dữ liệu live nếu luồng Socket.IO hoàn tất |
| Báo cáo & Demo | Kiểm thử tích hợp đầu-cuối; báo cáo có bằng chứng về DB, hiệu năng, bảo mật, backup, kiến trúc/API và giao diện; kịch bản demo, phương án dự phòng và chuẩn bị vấn đáp |

Danh sách chi tiết, thứ tự và người phụ trách nằm trong backlog Jira. Không xem
các mục trong bảng là đã triển khai chỉ vì chúng được đánh dấu Must.

### Should — làm sau Must nếu còn năng lực

- Tra cứu thông tin Node bằng trang web quét QR và API tra cứu marker.
- Báo cáo xu hướng telemetry theo Rack/Node.
- View/CTE dựng cây hạ tầng.
- View tài sản và cảnh báo bảo hành sắp hết hạn.

Các hạng mục này tương ứng với nhãn `should` trong CSV Jira hiện tại. Nếu thiếu
thời gian, giữ trạng thái chưa làm và không làm ảnh hưởng tiêu chí Must.

### Could — chỉ làm khi Must/Should đã ổn định

- Columnstore index cho truy vấn báo cáo; chỉ nhận việc khi có dữ liệu đo cho
  thấy lợi ích và còn thời gian.

### Won't — ngoài phạm vi phiên bản này

- AR thực tế, nhận diện/hiển thị bằng ArUco; QR trên web là phương án tra cứu
  được chọn.
- mTLS.
- PUE.
- Vận hành nhiều site như một hệ thống multi-site hoàn chỉnh. Mô hình có thực
  thể `Site` không đồng nghĩa tính năng multi-site đã được cam kết.
- Hash-chain audit.
- Ứng dụng mobile native; trải nghiệm mobile giới hạn ở web responsive/quét QR.

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

## Giới hạn chưa được coi là xác nhận

- CSV hiện có 4 task chuẩn bị vấn đáp theo vai A–D, trong khi quy mô nhóm là 5
  sinh viên. Nhóm cần phân công thành viên thứ năm trên Jira; tài liệu không tự
  suy đoán vai trò.
- Tên cột `Labels` bị lặp nhiều lần trong CSV. Trước khi import, cần kiểm tra
  mapping Jira để các nhãn Epic, MoSCoW, workstream, tuần và vai trò không bị
  ghi đè hoặc bỏ sót.
