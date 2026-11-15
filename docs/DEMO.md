# Kịch bản demo AR-IMMS

Mục tiêu: chứng minh luồng `collector → Flask API → SQL Server`.

## Chuẩn bị

- SQL Server Docker đang ở trạng thái `healthy`.
- Đã chạy schema, seed và `database/08_dev_node_api_key.sql`.
- Đã cài dependency trong `backend/requirements.txt`.
- Có `.env` cục bộ với `DATABASE_URL`.

## Bước 1: Khởi động Flask

```powershell
.\.venv\Scripts\python.exe backend/app.py
```

Kiểm tra health:

```powershell
Invoke-RestMethod http://localhost:5000/health
```

Kết quả mong đợi:

```json
{"status":"healthy","database":"connected"}
```

## Bước 2: Gửi telemetry hợp lệ

```powershell
$body = @{
  metric_type = "cpu_usage_percent"
  value = 42.5
  unit = "%"
} | ConvertTo-Json

Invoke-RestMethod `
  -Method Post `
  -Uri http://localhost:5000/telemetry `
  -Headers @{ "X-API-Key" = "demo-node-key-001" } `
  -ContentType "application/json" `
  -Body $body
```

Kết quả mong đợi là HTTP `201` với `status=recorded`.

## Bước 3: Kiểm tra lỗi và transaction

- Không có `X-API-Key` hoặc key sai: HTTP `401`.
- Body không phải JSON object hoặc thiếu trường: HTTP `400`.
- `node_id` không khớp agent: HTTP `403`.
- Metric/unit không hợp lệ: HTTP `422`.
- Kiểm tra `telemetry_metrics` để xác nhận request lỗi không tạo thêm dòng.

## Bước 4: Chạy test tự động

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s backend -p "test_*.py" -v
```

Các ca chính gồm API key hợp lệ, key sai, thiếu key, node không khớp,
unit sai và body sai.

## Phương án dự phòng

- Nếu collector không chạy, gửi request bằng PowerShell như bước 2.
- Nếu SQL Server chưa healthy, kiểm tra `docker compose ps` và log container.
- Không dùng backend Node.js/Next.js trong demo nhóm khi chưa được nhóm chốt
  lại kiến trúc.
