# AR-IMMS Collector

Collector thu thập CPU / RAM / disk (và nhiệt độ nếu máy có cảm biến) rồi gửi
từng metric lên `POST /telemetry` của Flask API mỗi 5 giây.

Mỗi lần gửi kèm header `X-API-Key`; Flask dùng key này để tra
`data_collector_agents` và tự gán `node_id`, nên collector không cần đăng nhập.

## Cài đặt

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r collector/requirements.txt
Copy-Item collector/.env.example collector/.env
```

Sửa `collector/.env` cho đúng môi trường. File này đã được `.gitignore`.
`API_KEY` không commit.

| Biến | Ý nghĩa | Mặc định |
| --- | --- | --- |
| `API_URL` | Endpoint nhận telemetry | `http://localhost:5000/telemetry` |
| `API_KEY` | API key của agent | — |
| `NODE_ID` | Node tương ứng với key | `1` |
| `INTERVAL_SECONDS` | Chu kỳ gửi, giây | `5` |
| `QUEUE_FILE` | File queue offline | `telemetry-queue-node<N>.jsonl` |
| `QUEUE_MAX_ITEMS` | Số mẫu tối đa khi offline | `1000` |

`API_KEY` phải khớp hash SHA-256 trong `data_collector_agents` (xem
`database/migrations/08_dev_node_api_key.sql`). Key sai bị Flask trả `401`.

## Chạy

```powershell
.\.venv\Scripts\python.exe collector/agent.py
```

Nhấn `Ctrl+C` để dừng.

## Offline queue

Collector phân biệt ba kết quả khi gửi:

| Kết quả | Xử lý |
| --- | --- |
| `2xx` | Bỏ khỏi queue, coi như đã ghi |
| Mất mạng / timeout / `5xx` | Giữ trong queue, retry với backoff (0.5s → 4s) |
| `4xx` | Bỏ mẫu, không retry, không vào queue (lỗi dữ liệu vĩnh viễn) |

Queue lưu dạng JSONL, nạp lại khi khởi động nên mẫu chưa gửi được vẫn còn sau
khi restart. Giới hạn `QUEUE_MAX_ITEMS` (mặc định 1000), mẫu cũ nhất bị loại khi
vượt ngưỡng.

## Test

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s collector/tests -v
```

Test dùng HTTP server nội bộ, không gọi SQL Server thật.

