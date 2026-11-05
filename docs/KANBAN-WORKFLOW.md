# Quy trình Kanban AR-IMMS

## Mục đích và nguồn theo dõi

Nhóm kéo công việc liên tục qua Jira Kanban; không chia backlog thành sprint.
CSV import Jira là bản khởi tạo backlog với 10 Epic và các nhãn MoSCoW,
workstream, tuần dự kiến và vai trò. Sau khi nhập, Jira theo dõi issue và trạng
thái; [STATUS.md](STATUS.md) ghi tóm tắt tiến độ cùng bằng chứng kiểm chứng.

Các giá trị W1–W5 trong CSV là mốc dự kiến trong khung đồ án 6 tuần, không phải
cam kết sprint. Mục tiêu vẫn là chốt phạm vi/schema Must cuối tuần 4 theo
[SCOPE-MOSCOW.md](SCOPE-MOSCOW.md).

## Cột board đề xuất

Jira CSV chưa chứa cấu hình trạng thái/WIP đã xác nhận. Đây là cấu hình khởi
đầu đề xuất cho task Jira "Thiết lập Jira Kanban"; cần nhóm cấu hình và xác nhận
trên board trước khi coi là chính sách đã áp dụng.

| Cột | Ý nghĩa | Điều kiện vào / ra |
|---|---|---|
| Backlog | Việc đã ghi nhận, chưa sẵn sàng kéo | Vào: có mục tiêu và Epic; ra: đã ưu tiên, đủ DoR |
| Ready | Việc sẵn sàng và đã được xếp ưu tiên | Vào: đạt DoR, có người nhận hoặc nhóm nhận; ra: còn chỗ WIP ở In Progress |
| In Progress | Đang triển khai | Vào: có người chịu trách nhiệm và phạm vi rõ; ra: thay đổi hoàn tất, có test/bằng chứng để review |
| Review | Đang review thiết kế/code/script/tài liệu | Vào: có diff và hướng dẫn kiểm tra; ra: đạt tiêu chí review hoặc trả lại In Progress với lý do |
| Verify | Đang chạy kiểm thử tích hợp, nghiệm thu hoặc demo | Vào: review đạt, môi trường và test sẵn sàng; ra: kết quả đạt thì Done, lỗi thì quay lại In Progress |
| Done | Đạt Definition of Done | Chỉ vào khi có bằng chứng và cập nhật tài liệu/trạng thái liên quan |

`Blocked` nên là flag/trạng thái cản trở trên issue, không phải cột chứa việc
không nhìn thấy trong luồng. Issue bị block giữ vị trí hiện tại, ghi rõ nguyên
nhân, người cần hỗ trợ và bước gỡ; rà soát hàng tuần.

## WIP limit khởi đầu đề xuất

Với nhóm 5 người, thử các giới hạn sau trong một tuần làm việc rồi điều chỉnh
dựa trên nút thắt thực tế:

| Cột | WIP tối đa đề xuất |
|---|---:|
| Ready | 5 |
| In Progress | 3 |
| Review | 2 |
| Verify | 2 |

Backlog và Done không giới hạn. Một issue có nhiều người làm vẫn tính là một
thẻ WIP; ưu tiên hoàn thành hoặc hỗ trợ thẻ đang dở trước khi kéo việc mới.
Không vượt WIP mà không ghi lý do và thời hạn xử lý.

## Definition of Ready (DoR)

Issue có thể chuyển sang Ready khi:

- Có mục tiêu/ngữ cảnh nghiệp vụ rõ và thuộc Epic/phạm vi MoSCoW.
- Mô tả được đầu ra có thể kiểm tra và tiêu chí chấp nhận.
- Phụ thuộc, rủi ro và dữ liệu/môi trường cần thiết đã được nêu.
- Với thay đổi DB: nêu bảng/object liên quan, ảnh hưởng dữ liệu cũ, transaction
  hoặc migration dự kiến và kịch bản kiểm thử.
- Với API/UI/collector: nêu contract hoặc luồng liên quan; không tự ý đổi REST
  API contract.
- Issue đủ nhỏ để nhóm hoàn tất, review và verify trong một luồng ngắn; nếu
  không, tách thành các issue có đầu ra độc lập.
- Có nhãn Epic, ưu tiên/MoSCoW, workstream và người phụ trách theo cấu hình
  Jira nhóm đã thống nhất.

## Definition of Done (DoD)

Issue chỉ chuyển Done khi:

- Tiêu chí chấp nhận đã được kiểm tra; kết quả PASS hoặc bằng chứng tương đương
  được đính kèm.
- Code/script được review; không đưa secrets hoặc dữ liệu nhạy cảm vào repo.
- Thay đổi DB có script cập nhật, khả năng chạy lại/migration được kiểm tra và
  test case SQL được ghi nhận.
- Tài liệu liên quan, ERD/từ điển dữ liệu, API contract hoặc hướng dẫn vận hành
  được cập nhật khi bị ảnh hưởng.
- Kiểm tra tích hợp các bề mặt bị tác động (backend, DB, collector, web) đã chạy
  hoặc giới hạn kiểm tra được ghi rõ.
- `STATUS.md` được cập nhật nếu kết quả làm thay đổi trạng thái tổng thể hoặc có
  bằng chứng mới cần giữ.
- Không còn blocker chưa xử lý; Jira phản ánh đúng kết quả, PR/commit hoặc
  artifact liên quan được liên kết nếu có.

## Nhịp làm việc

- **Replenishment:** họp tuần theo task Jira để ưu tiên Ready, kiểm tra MoSCoW,
  phụ thuộc và WIP; không kéo Should/Could nếu Must đang bị nghẽn.
- **Flow check:** nhóm trao đổi ngắn thường xuyên để xử lý thẻ bị block và hỗ trợ
  Review/Verify đang vượt WIP. Không yêu cầu mọi người cập nhật theo nghi thức
  sprint.
- **Review/retro tuần:** xem số thẻ Done, thời gian chờ ở Review/Verify và tuổi
  blocker; chọn một cải tiến cụ thể cho tuần kế tiếp. Không đặt chỉ tiêu throughput
  trước khi có dữ liệu thực.
- **Mốc W4:** rà soát và đóng băng Must schema/phạm vi; mọi ngoại lệ cần ghi lý
  do và ảnh hưởng.
- **Mốc cuối:** kiểm thử tích hợp, restore demo, báo cáo, kịch bản demo và chuẩn
  bị vấn đáp theo DoD.

## Jira import và nhãn

CSV hiện dùng nhiều cột cùng tên `Labels` để mang các nhóm nhãn khác nhau.
Trước khi import, kiểm tra mapping Jira: nếu công cụ không hỗ trợ lặp trường,
gộp các giá trị vào một trường Labels nhiều giá trị và bảo đảm không mất nhóm
nhãn Epic, MoSCoW (`must`/`should`/`could`), workstream, tuần và role. Kiểm tra
Parent/Epic mapping bằng một lần import thử hoặc bản xem trước trước khi nhập cả
backlog.

CSV cũng có bốn task chuẩn bị vấn đáp (A–D), trong khi quy mô nhóm là năm
người. Bổ sung phân công cho thành viên thứ năm trong Jira thay vì suy luận từ
nhãn role.
