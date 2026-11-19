# Partition `telemetry_metrics` theo ngày (HQTCSDL-36)

Mục tiêu (Jira): dữ liệu chia đúng partition theo ngày; truy vấn theo ngày chỉ quét partition cần.
Ghi chú tên cột: `collected_at` trong issue là cột thời gian của `telemetry_metrics` (trước đây tên `timestamp`).
Đã đổi tên cột trong `02`, `03`, `04`, `05`, `16` và từ điển dữ liệu; DB cũ được đổi tên tự động khi chạy lại `02`.

## 1. Thiết kế

| Thành phần | Giá trị |
|---|---|
| Cột partition | `collected_at` (`DATETIME2`, UTC) |
| Partition function | `pf_telemetry_day`, `RANGE RIGHT`, mỗi mốc là 00:00 UTC (00:00:00 thuộc ngày mới) |
| Cửa sổ ban đầu | 35 ngày trước đến 14 ngày sau ngày chạy; dòng cũ hơn mốc đầu dồn vào partition 1 |
| Partition scheme | `ps_telemetry_day`, tất cả partition trên filegroup `PRIMARY` |
| Clustered index | `CIX_telemetry_collected_at_node (collected_at, node_id)` |
| Khóa chính | `PK_telemetry_metrics` NONCLUSTERED `(id, collected_at)` cùng partition (PK phải chứa cột partition) |
| Index không cụm | `IX_telemetry_node_time`, `IX_telemetry_metric_type_time` tạo lại theo partition |
| Duy trì | `usp_extend_telemetry_partitions @days_ahead` thêm mốc cho các ngày sắp tới (`SPLIT RANGE`) |

Đánh đổi: PK `(id, collected_at)` không còn ép duy nhất cho riêng `id` ở mức DB; `id` là identity nên vẫn duy nhất
trong thực tế. Job retention hiện có vẫn xóa bằng `DELETE`, chưa chuyển sang xóa theo partition.

## 2. Thứ tự chạy

1. `01` → `05` (bản mới đã đổi `collected_at`), `16`.
2. Backup nếu DB có dữ liệu quan trọng.
3. `19` PHẦN A1 (sinh 100.000 dòng thử trải 7 ngày) và A2 (**đo TRƯỚC**, ghi lại logical reads và thời gian).
4. `18_telemetry_partition.sql`, chụp 2 truy vấn kiểm tra cuối script (số dòng theo partition, danh sách index).
5. `19` PHẦN A2 lần nữa (**đo SAU**, bật Actual Execution Plan, xem Actual Partition Count).
6. `19` PHẦN B (P1..P7), chụp bảng kết quả.
7. Chạy lại `06_verify_seed_data.sql`, `07_test_normalized_schema.sql`, rồi `POST /telemetry` (HTTP 201).
8. `19` PHẦN C (dọn dữ liệu thử).

## 3. Test case

| Mã | Kịch bản | Kết quả mong đợi |
|---|---|---|
| P1 | Chạy `17` 2 lần liên tiếp (lần 2 in `SKIP`); kiểm tra cấu trúc index | Không lỗi; clustered `(collected_at, node_id)` trên partition scheme, PK không cụm |
| P2 | Tổng số dòng các partition so với `COUNT(*)`; `17` đã tự so số dòng trước/sau | Bằng nhau, không mất dòng |
| P3 | Chèn dòng 00:00, 12:00, 23:59:59.99 của ngày D và 00:00 ngày D+1 | 3 dòng đầu cùng partition, dòng cuối ở partition kế tiếp |
| P4 | Dữ liệu của 1 ngày nằm trong mấy partition; plan truy vấn 1 ngày | 1 partition; `Actual Partition Count = 1` |
| P5 | Ghi 1 dòng bằng `usp_record_telemetry` | Dòng nằm ở partition của ngày hôm nay |
| P6 | Chạy `usp_extend_telemetry_partitions` 2 lần | Lần 2 không thêm mốc trùng |
| P7 | `vw_latest_telemetry`, `vw_dashboard_summary`, `06`, `07`, `POST /telemetry` | Vẫn chạy đúng, API trả 201 |

## 4. Kết quả đo (điền số thật sau khi chạy)

Truy vấn: `COUNT(*)`, `AVG(value)` cho 1 ngày (`collected_at >= @d1 AND collected_at < @d2`), 100.000 dòng thử trải 7 ngày.

| | Trước partition | Sau partition |
|---|---|---|
| Logical reads | 512 | 79 |
| CPU time / elapsed time (ms) | 15/25 | 16/80 |
| Actual Partition Count (plan) | không áp dụng | 2 |

Kết quả P1..P7: Pass.


Lưu ý khi viết truy vấn: điều kiện phải đặt trực tiếp trên `collected_at` (không bọc trong `CAST`/`CONVERT`) thì mới loại được
partition; truy vấn không lọc theo ngày (ví dụ `vw_latest_telemetry`) vẫn quét mọi partition.

