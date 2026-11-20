# Đo trước/sau partition: execution plan, STATISTICS IO/TIME (HQTCSDL-37)

Mục tiêu (Jira): bảng so sánh thời gian và ảnh execution plan cho 3 truy vấn, trước và sau thay đổi của HQTCSDL-36
(partition theo ngày + clustered index `(collected_at, node_id)`).

## 1. Phương pháp

Dùng **hai bảng thử chứa cùng dữ liệu**, chạy cùng truy vấn trong cùng phiên SSMS (`database/25_perf_before_after.sql`):

| Bảng | Thiết kế |
|---|---|
| `perf_telemetry_before` | Thiết kế cũ: PK clustered trên `id`; index không cụm `(node_id, collected_at DESC)` và `(metric_type_id, collected_at DESC)` |
| `perf_telemetry_after` | Thiết kế mới: partition theo ngày (`ps_telemetry_day`), clustered `(collected_at, node_id)`, PK không cụm `(id, collected_at)`, 2 index không cụm cùng partition |

Cách này không đụng vào `telemetry_metrics` thật, không cần hoàn tác partition, và chạy lại được. Dữ liệu thử:
khoảng 2.000.000 dòng trải 14 ngày UTC liên tiếp, thời gian tăng đều theo `id` (giống dữ liệu ingest), node và loại chỉ số lấy
từ `nodes` và `metric_types` thật, gán xoay vòng.

## 2. Ba truy vấn

| Mã | Nội dung | Ghi chú |
|---|---|---|
| Q1 | `COUNT(*)`, `AVG(value)` trong 1 ngày | Điều kiện theo ngày: kỳ vọng chỉ truy cập 1 partition |
| Q2 | `COUNT`, `MIN`, `MAX`, `AVG` của 1 node trong 24 giờ cuối | Lọc cả `node_id` và `collected_at` |
| Q3 | `COUNT`, `AVG`, `MAX` theo `metric_type_id` trong 3 ngày cuối | Kỳ vọng truy cập 3 partition thay vì cả bảng |

Mọi truy vấn dùng `OPTION (RECOMPILE)` để ước lượng theo giá trị thật của tham số, hai bảng được so sánh công bằng.
Điều kiện thời gian đặt trực tiếp trên cột `collected_at` (không bọc `CAST`/`CONVERT`).

## 3. Cách chạy lại

1. Đã chạy `01..05`, `16`, `17`. Backup nếu cần. Đóng bớt chương trình (laptop 4 GB RAM); nên đặt `max server memory` khoảng 1536 MB.
2. Mở `19_perf_before_after.sql`, cùng một cửa sổ: PHẦN 1 (sinh dữ liệu; chạy lại thì in `SKIP`), PHẦN 2 (kiểm tra, chụp ảnh).
3. PHẦN 3: chạy 3.0 rồi lần lượt các batch Q1..Q3 (mỗi batch tự lặp 3 lần), cuối cùng là bảng so sánh 3.7 (chụp ảnh).
4. PHẦN 4: bật *Include Actual Execution Plan* (Ctrl+M), chạy từng khối Q1..Q3, chụp plan 2 bảng và tab Messages
   (STATISTICS IO/TIME). Chuột phải toán tử trên plan bảng `after` → Properties → *Actual Partition Count*. Lưu plan thành `.sqlplan` để đính kèm.
Lưu ý khi đọc số liệu: số `logical reads` ổn định giữa các lần chạy, còn CPU và elapsed time dao động theo máy; bảng so sánh
lấy lần nhanh nhất trong 3 lần. Đo lạnh (xóa cache) là phép đo khác, cần ghi rõ nếu dùng.

## 4. Test case

| Mã | Kịch bản | Kết quả mong đợi |
|---|---|---|
| R1 | Số dòng hai bảng | Bằng nhau |
| R2 | Số dòng theo từng ngày | Giống nhau ở cả 2 bảng |
| R3 | Kết quả Q1 | Giống nhau (cùng số dòng, trung bình) |
| R4 | Kết quả Q2 | Giống nhau (cùng số điểm, thời điểm sớm/muộn nhất, trung bình) |
| R5 | Kết quả Q3 | Giống nhau theo từng loại chỉ số |


## 5. Ý chính để giải thích trong 2 phút
- Bảng cũ cluster theo `id`, nên truy vấn theo ngày không có chỗ để tìm: phải quét cả bảng.
- Bảng mới chia theo ngày và cluster theo `(collected_at, node_id)`: điều kiện theo ngày chỉ chạm các partition của ngày đó
  (*partition elimination*), nên số trang đọc giảm xấp xỉ theo tỷ lệ số ngày truy cập trên tổng số ngày.
- Truy vấn không lọc theo ngày (ví dụ `vw_latest_telemetry`) vẫn quét mọi partition, không được lợi.
- Cách đo: hai bảng cùng dữ liệu, cùng truy vấn, `STATISTICS IO/TIME` và Actual Execution Plan, kiểm tra kết quả hai bên trùng nhau.
