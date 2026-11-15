# Load test ingest (HQTCSDL-27)

Mục tiêu: báo cáo tốc độ ghi khi gửi vài chục dòng/giây, không có lỗi.

## 1. Môi trường đo

| Hạng mục | Giá trị |
|---|---|
| Máy | Laptop 4 GB RAM (không chạy nổi Docker nên test trên SQL Server cài trực tiếp) |
| SQL Server | Enterprise Developer 64-bit, instance `SQLDEV` trên Windows |
| Backend | Flask (`flask --app app run --port 5000`), **debug tắt**, server phát triển 1 tiến trình |
| Python | 3.9, thư viện `requests` cho client |
| Dữ liệu | Agent demo `demo-node-key-001` (`database/08_dev_node_api_key.sql`) |
| Cấu hình client | 20 luồng song song, giữ nhịp theo từng mức tải |

Mỗi request ghi 1 chỉ số vào `telemetry_metrics` qua `usp_record_telemetry`.
Giá trị sinh ngẫu nhiên **dưới ngưỡng cảnh báo** (CPU 10–60, RAM 20–70, đĩa 15–70, nhiệt độ 30–60)
nên không đổi trạng thái node và không sinh alert.

## 2. Cách chạy lại

1. Bật SQL Server + SQL Server Agent, chạy `database/01..05` và `08_dev_node_api_key.sql`.
2. Cửa sổ 1 (backend): `cd backend` → `flask --app app run --port 5000`; kiểm tra `http://127.0.0.1:5000/health`.
3. Ghi mốc trước khi chạy (SSMS, DB `AR_IMMS`):
   ```sql
   SELECT COUNT(*) AS so_dong_truoc, MAX(id) AS id_lon_nhat_truoc FROM telemetry_metrics;
   SELECT COUNT(*) AS so_alert_truoc FROM alerts;
   ```
4. Cửa sổ 2 (client): `$env:LOAD_TEST_URL = 'http://127.0.0.1:5000/telemetry'` rồi `python backend\load_test_ingest.py`.
5. Đối chiếu sau khi chạy:
   ```sql
   SELECT COUNT(*) AS so_dong_sau FROM telemetry_metrics;
   SELECT COUNT(*) AS so_alert_sau FROM alerts;
   ```
6. Dọn dữ liệu test: `DELETE FROM telemetry_metrics WHERE id > <id_lon_nhat_truoc>;`

## 3. Test case

| Mã | Kịch bản | Kết quả mong đợi |
|---|---|---|
| LT-01 | Gửi 10 req/s trong 20 giây (200 request) | 200 phản hồi 201, 0 lỗi |
| LT-02 | Gửi 30 req/s trong 20 giây (600 request) | 600 phản hồi 201, 0 lỗi |
| LT-03 | Gửi 50 req/s trong 30 giây (1500 request) | 1500 phản hồi 201, 0 lỗi |
| LT-04 | Đối chiếu DB | `so_dong_sau - so_dong_truoc` = tổng số phản hồi 201 |
| LT-05 | Không tác dụng phụ | `so_alert` và trạng thái node không đổi |
| LT-06 | Chạy lại script lần 2 | Kết quả tương tự, LT-04 vẫn khớp |

## 4. Kết quả đo (lần chạy dùng `127.0.0.1`)

| Mức tải mục tiêu (req/s) | Số gửi | Số 201 | Tốc độ ghi thực tế (req/s) | p50 (ms) | p95 (ms) | p99 (ms) | Lỗi |
|---:|---:|---:|---:|---:|---:|---:|---|
| 10 | 200 | 200 | 10.0 | 32.6 | 59.1 | 76.1 | 0 |
| 30 | 600 | 600 | 30.0 | 23.0 | 30.5 | 33.2 | 0 |
| 50 | 1500 | 1500 | 50.0 | 19.4 | 29.8 | 38.1 | 0 |

Tổng 2300 request, 2300 thành công (HTTP 201), 0 lỗi.

Đối chiếu DB: `so_dong_truoc` = 18, `so_dong_sau` = 2318, chênh lệch = 2300.
`so_alert` trước/sau = 1 / 1.

### Lưu ý khi đọc số liệu
- **Tốc độ thực tế bằng đúng mức tải đặt ra** ở cả ba mức. Nghĩa là hệ thống đáp ứng được 50 req/s trên máy này;
  bài test này **không** tìm ra ngưỡng tối đa (muốn biết ngưỡng cần tăng thêm mức tải).
- Độ trễ mức 10 req/s cao hơn hai mức sau. Mức này chạy đầu tiên nên có thể gồm thời gian khởi tạo kết nối ban đầu (chưa kiểm chứng riêng).
- Lần chạy đầu dùng địa chỉ `localhost` cho kết quả khác hẳn: p50 ≈ 2098 ms và chỉ ~9 req/s ở mọi mức.
  Chỉ đổi địa chỉ thành `127.0.0.1` thì độ trễ giảm còn vài chục ms. Nghi do `localhost` được thử bằng IPv6 trước
  rồi mới sang IPv4 (cơ chế này chưa kiểm chứng trực tiếp). Vì vậy **khi đo luôn dùng `127.0.0.1`**.
- Số liệu là của máy 4 GB RAM, backend chạy bằng server phát triển của Flask; máy hoặc server khác sẽ cho số khác.
