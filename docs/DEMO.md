# Kịch bản demo AR-IMMS (5 phút)

Mục tiêu: chứng minh luồng end-to-end từ collector → DB → web → ticket → audit.

## Chuẩn bị
- SQL Server Docker đang chạy, schema + seed đã có
- web (Next.js) đang chạy trên localhost:3000
- Collector chạy trên ít nhất 2 máy (hoặc 2 terminal cùng máy, khác node_id)

## Bước 1: Hiện trạng bình thường
- Mở web, đăng nhập bằng tài khoản Operator
- Thấy cây Site → Room → Rack → Node với số liệu sống (CPU, RAM, disk)
- Node status = OK (xanh), số liệu cập nhật mỗi 5 giây

## Bước 2: Kích hoạt alert
- **Cách A**: Ép CPU > 90% trên máy collector (chạy stress test hoặc vòng lặp vô hạn)
- **Cách B**: Tắt collector 90 giây → node chuyển UNAVAILABLE
- Trên web: alert xuất hiện (đỏ), node status đổi sang CRITICAL hoặc UNAVAILABLE
- **Quan trọng**: gửi tiếp cùng metric vượt ngưỡng → KHÔNG tạo thêm alert trùng

## Bước 3: Xử lý ticket
- Operator tạo ticket từ alert, giao cho Technician
- Đăng nhập bằng tài khoản Technician
- Technician thấy ticket được giao, mở chi tiết

## Bước 4: Quét QR trên điện thoại
- Mở web trên điện thoại (cùng LAN, truy cập qua IP:3000)
- Vào trang /scan, quét mã QR dán trên node
- Thấy telemetry mới nhất của node đó (CPU, RAM, disk, status)
- Ghi chú vào ticket, gửi yêu cầu đóng ticket

## Bước 5: Duyệt đóng ticket
- Đăng nhập lại bằng Operator
- Operator duyệt yêu cầu đóng ticket
- Ticket chuyển sang CLOSED

## Bước 6: Audit log
- Xem audit log: thấy các sự kiện đã diễn ra (alert tạo, ticket tạo, trạng thái
  đổi, ticket đóng) với đúng thời gian và người thực hiện

## Phương án dự phòng
- Quay video demo trước ngày 28/11
- Nếu collector không chạy trên 2 máy thật: dùng 2 terminal cùng máy, khác NODE_ID
- Nếu QR camera không hoạt động trên mạng hội trường: chiếu video quay sẵn phần QR
- Nếu mạng hội trường hỏng: chạy toàn bộ trên localhost/hotspot riêng
