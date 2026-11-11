# Trạng thái dự án AR-IMMS

Cập nhật: 2026-11-11

## Hiện trạng thực tế

### Đã có (đã xác minh chạy được)
- Schema SQL Server 25 bảng: `database/01–07.sql`, `08_telemetry_wide...sql`
- Bảng `telemetry_wide` + `node_latest` (script 08)
- SP `sp_record_telemetry`, `sp_check_stale_nodes` (tiền tố cũ, cần đổi thành `usp_`)
- Trigger audit, view `vw_hierarchy_tree` (script 04)
- Docker Compose: SQL Server + SQL Agent, giới hạn RAM, mount backup
- Scripts: `06_verify_seed_data.sql` PASS, `07_test_normalized_schema.sql` PASS

### Chưa có
- Tầng ứng dụng: web, API, collector — chưa tồn tại
- SP `usp_authenticate_user`, `usp_authenticate_agent`, `usp_list_nodes_latest`, `usp_list_alerts`
- Logic alert trong `usp_record_telemetry_wide` (SP rộng chưa có alert, chống trùng)
- Hash mật khẩu seed = placeholder, chưa đăng nhập được
- SQL Login/User/Role/GRANT
- Đo hiệu năng (index, partition, STATISTICS IO)
- Backup/restore có bằng chứng

## Dữ liệu mẫu cục bộ (không commit vào git)

| Tài khoản | Mật khẩu demo | Ghi chú |
|---|---|---|
| admin | _chưa có hash thật_ | Seed chỉ có placeholder |
| operator | _chưa có hash thật_ | — |
| technician | _chưa có hash thật_ | — |

Sau khi DB agent chạy script 09 + 10: ghi hash và agent key mẫu vào đây.

## Việc cần làm ngay (hôm nay 11/11)

1. **DB**: Script 09 đổi tên `usp_`, mở rộng `usp_record_telemetry_wide` (alert +
   node status từ `alert_thresholds`), `usp_authenticate_*`, `usp_list_*`, seed hash bcrypt thật
2. **Web**: Next.js init, `web/lib/db.ts` với `callSp()`, routes theo `docs/API.md`
3. **Collector**: `collector/collector.py` psutil + retry + buffer

Cuối ngày 11/11 bắt buộc đạt: `POST /api/telemetry` → 201, `GET /api/nodes` trả CPU sống.

## Lệnh kiểm chứng (cập nhật khi có)

```bash
# Health check
curl http://localhost:3000/api/health

# Đăng nhập, lấy token
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"operator","password":"demo123"}'

# Gửi telemetry (thay AGENT_KEY và NODE_ID)
curl -X POST http://localhost:3000/api/telemetry \
  -H "X-Agent-Key: AGENT_KEY" \
  -H "Content-Type: application/json" \
  -d '{"node_id":1,"collected_at":"2026-11-11T10:00:00Z","cpu_usage_percent":45.2,...}'

# Lấy danh sách node (thay TOKEN)
curl http://localhost:3000/api/nodes \
  -H "Authorization: Bearer TOKEN"
```
