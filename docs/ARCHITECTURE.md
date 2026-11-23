# Kiến trúc AR-IMMS

## Mục tiêu

AR-IMMS giám sát telemetry và hỗ trợ bảo trì một Mini Data Center testbed. Mô hình số gồm `Site → Room → Rack → Node → Container`.

## Thành phần

| Thành phần | Trách nhiệm | Kết nối dữ liệu |
|---|---|---|
| SQL Server Developer | Lưu schema/nghiệp vụ, thực thi constraint, transaction, procedure, trigger, view và function | Cơ sở dữ liệu duy nhất của bản nộp |
| Flask backend (`backend/`) | REST API, xác thực/ủy quyền, validation tại biên, gọi procedure | SQLAlchemy quản lý kết nối/pool; pyodbc driver; không ORM nghiệp vụ |

Cấu trúc backend: `backend/api/` (blueprints), `backend/core/` (config, extensions, security), `backend/db/` (stored-procedure gateway), `backend/tests/` (tests), `backend/tools/` (load tool). `backend/app.py` giữ vai trò entrypoint tương thích.
| Next.js (`web/`) | Dashboard và BFF cho trình duyệt | Gọi Flask; không kết nối SQL Server |
| Collector (`collector/`) | Thu thập host/container telemetry, batch và buffer/retry | Gửi HTTP đến Flask với `X-API-Key` |
| SQL Server Agent | Heartbeat/stale-node và các lịch backup/cleanup khi được cấu hình | Job chạy trong SQL Server |

## Luồng dữ liệu chính

```text
Collector -- X-API-Key + telemetry --> Flask
Flask -- EXEC dbo.usp_* --> SQL Server
SQL Server -- kết quả procedure --> Flask -- REST/SSE --> Next.js BFF/dashboard
```

Web không được bỏ qua backend để truy cập database. Việc kiểm tra trạng thái backend gọi `dbo.usp_health_check`.

### Telemetry

1. Collector lấy metrics và có thể đóng gói thành batch.
2. Backend xác thực API key, kiểm tra loại/đơn vị/giá trị và giới hạn kích thước batch.
3. Backend gọi `usp_record_telemetry` hoặc `usp_record_telemetry_batch`.
4. SQL Server ghi telemetry và cập nhật trạng thái/alert theo logic database.
5. Backend phát tín hiệu cập nhật tới client qua SSE; dashboard có fallback polling.

### Người dùng và ticket

1. Người dùng đăng nhập qua Flask; token/session được kiểm tra theo cơ chế hiện hành.
2. Route kiểm tra role và quyền tài nguyên.
3. Thao tác nghiệp vụ gọi stored procedure; lỗi nghiệp vụ SQL được ánh xạ sang response API.
4. Thay đổi quan trọng được audit ở database.

## Ranh giới trách nhiệm

- Constraint, transaction, quyền DB và logic dữ liệu nhất quán thuộc SQL Server.
- HTTP contract, authentication flow và validation đầu vào thuộc Flask.
- BFF/UI chịu trách nhiệm trình bày và điều phối HTTP, không quyết định quyền database.
- Collector chỉ gửi dữ liệu theo contract; không được giữ credential SQL Server.

## Giới hạn

- QR/AR là Mobile Web scanner/HUD, không phải ứng dụng native hoặc AR 3D SDK.
- Collector xác thực bằng API key; mTLS không thuộc phạm vi hiện tại.
- SSE là luồng sự kiện backend; không đảm bảo thay thế việc truy vấn trạng thái chuẩn từ database.


