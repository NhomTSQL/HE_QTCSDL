# Hướng dẫn người dùng

## Đăng nhập

1. Mở dashboard tại `http://localhost:3000`.
2. Đăng nhập bằng tài khoản được cấp.
3. Giao diện và API giới hạn chức năng theo vai trò Administrator, System Operator hoặc Field Technician.
4. Đổi ngôn ngữ EN/VI bằng điều khiển trên giao diện.

Không dùng mật khẩu seed placeholder. Môi trường demo đồng bộ mật khẩu cục bộ theo cấu hình `AR_IMMS_DEV_PASSWORD`.

## Overview và Digital Twin

- Duyệt cây `Site → Room → Rack → Node → Container`.
- Mở Node để xem trạng thái, telemetry, alert và container liên quan.
- Dùng tìm kiếm/phân trang nếu danh sách dài.

## Alerts và Tickets

- Operator xác nhận/acknowledge alert và phân công ticket theo quyền.
- Technician xem ticket được giao, thêm ghi chú và gửi yêu cầu đóng khi công việc hoàn tất.
- Operator/Admin xem xét yêu cầu đóng theo quy trình nghiệp vụ.
- Không coi việc gửi yêu cầu đóng là ticket đã đóng cho đến khi được duyệt.

## QR/marker và hiện trường

- Mở Mobile Web Scanner trên thiết bị có camera và cấp quyền camera.
- Quét QR/marker đã đăng ký hoặc chọn marker testbed.
- HUD hiển thị thông tin Node/telemetry theo dữ liệu backend.
- Chức năng này là web-based QR/AR overlay, không phải AR 3D native.

## Assets, Analytics và Admin

- Assets & Maintenance: xem hardware/NIC, warranty và maintenance history theo quyền.
- Analytics & PUE: xem telemetry trend, PUE/capacity và xuất CSV.
- Admin & Audit: quản lý account/agent và tra cứu audit logs theo quyền.

## Đăng xuất và an toàn

- Đăng xuất khi kết thúc phiên; phiên có thể bị thu hồi khi credential/role đổi.
- Không chia sẻ token, API key hoặc đường dẫn QR chứa thông tin nhạy cảm.
- Nếu nhận `401`, đăng nhập lại; nếu `503`, báo người vận hành kiểm tra backend/database.


