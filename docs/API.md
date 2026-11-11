# Hợp đồng API và Stored Procedure (đóng băng; muốn đổi phải được người dùng duyệt)

## REST (Next.js, thư mục web/app/api)
Quy ước: JSON, UTF-8, thời gian ISO-8601 UTC. Lỗi: { "error": "<thông báo chung>" }.

GET /api/health                      -> 200 { "status": "healthy", "database": "connected" } | 503
POST /api/auth/login                 -> body { "username": str, "password": str }
                                        200 { "token": str, "user": { "id": int, "username": str, "role": str } }
                                        401 sai thông tin | 400 thiếu trường
POST /api/telemetry                  -> header X-Agent-Key: <key>
                                        body (collected_at bắt buộc; các số đo có thể null):
                                        { "node_id": int, "collected_at": "2026-11-12T03:00:00Z",
                                          "cpu_usage_percent": 0-100, "memory_usage_percent": 0-100,
                                          "disk_usage_percent": 0-100, "temperature_celsius": number|null,
                                          "network_in_bytes": int>=0, "network_out_bytes": int>=0,
                                          "uptime_seconds": int>=0, "process_count": int>=0 }
                                        201 { "ok": true } | 400 dữ liệu sai | 401 agent key sai
                                        | 404 node không tồn tại
GET /api/nodes                       -> header Authorization: Bearer <JWT> (mọi role)
                                        200 [ { "id", "name", "rack_name", "room_name", "site_name",
                                          "status", "last_ping_at", "collected_at", "cpu_usage_percent",
                                          "memory_usage_percent", "disk_usage_percent" } ]
GET /api/alerts?status=OPEN,ACKNOWLEDGED -> Bearer JWT; 200 [ { "id", "node_id", "node_name",
                                          "alert_type", "severity", "status", "message", "metric_value",
                                          "triggered_at" } ]

## Stored procedure (schema dbo)
usp_authenticate_user   @username NVARCHAR(100)
    -> 0 hoặc 1 dòng: id, username, password_hash, role_code, is_active
usp_authenticate_agent  @key_hash CHAR(64)      -- SHA-256 hex của agent key, backend tự băm
    -> 0 hoặc 1 dòng: agent_id, node_id, is_active
usp_record_telemetry_wide  (chữ ký hiện có trong database/08; THROW 51050 khi node không tồn tại)
    -> ghi telemetry, cập nhật node_latest + nodes.status/last_ping_at, tạo alert chống trùng, ghi audit
usp_list_nodes_latest
    -> các cột như GET /api/nodes
usp_list_alerts         @statuses NVARCHAR(100)  -- danh sách phân tách bằng dấu phẩy
    -> các cột như GET /api/alerts
usp_check_stale_nodes   @stale_timeout_seconds INT = 90   -- gọi bởi SQL Server Agent job

Lưu ý: tên cột thực tế có thể khác; DB agent điều chỉnh bên trong SP để TRẢ VỀ ĐÚNG tên cột ở trên.
