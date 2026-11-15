# Trạng thái dự án AR-IMMS

Cập nhật: 2026-11-15 (HQTCSDL-24 batch ingest)

## Hiện trạng thực tế

### Đã có (đã xác minh chạy được)
- Schema SQL Server 25 bảng: `database/01–07.sql`, `08_telemetry_wide...sql`
- Bảng `telemetry_wide` + `node_latest` (script 08)
- API SP vertical slice: `database/09_api_vertical_slice.sql`
- Auth bcrypt demo + SHA-256 agent key seed
- Alert threshold, deduplication, auto-resolve, node status, audit
- Trigger audit, view `vw_hierarchy_tree` (script 04)
- Docker Compose: SQL Server + SQL Agent, container healthy
- Scripts `06`, `07`, `10_test_api_vertical_slice.sql`: PASS
- Next.js API + dashboard, Collector Python + offline queue
- E2E API: health 200, login 200, telemetry 201, nodes/alerts trả dữ liệu
- Collector unit tests: 3/3 PASS; TypeScript check: PASS

**Sprint 13–17/11 (đã hoàn thành):**
- `database/11_ticket_management.sql`: 9 SP vòng đời ticket + seed marker QR, PASS
- `database/12_test_ticket_management.sql`: toàn bộ PASS, non-destructive
- `database/13_user_directory.sql`: `usp_list_technicians`, `usp_list_users` — PASS
- `database/14_test_user_directory.sql`: toàn bộ PASS
- API routes ticket: `GET/POST /api/tickets`, `GET /api/tickets/[id]`, assign, accept, notes, closure-request, review
- API route marker: `GET /api/markers/[code]`
- API route user: `GET /api/users/technicians`, `GET /api/users`
- `web/lib/session.ts`: JWT vào sessionStorage, `decodeToken`, `decodeRole`
- `web/lib/apiAuth.ts`: `authenticate`, `requireRoles`, `isPayload`
- `web/lib/spErrors.ts`: map lỗi SP → HTTP 400/404/409/503
- `web/lib/db.ts`: thêm `callSpMulti` cho SP nhiều result set
- Dashboard (`/`): panel Ticket (tạo từ alert, gán technician, duyệt/từ chối closure)
- Trang quét QR (`/scan`): camera + nhập tay, hiện node metrics, ticket của node, tiếp nhận / ghi chú / yêu cầu đóng
- CSS responsive: layout 720px mobile cho ticket và scan

**HQTCSDL-24 — batch telemetry (2026-11-15):**
- `database/23_ingest_telemetry_batch.sql`: `dbo.usp_ingest_telemetry` nhận JSON array, parse bằng `OPENJSON`, insert nhiều `telemetry_metrics` trong một transaction; lỗi giữa batch rollback toàn bộ. Timestamp yêu cầu ISO-8601 có timezone và lưu UTC `datetime2`.
- `database/23_test_ingest_telemetry_batch.sql`: xác nhận một lần gọi ghi 3 metric; metric code sai ở phần tử sau không để lại hàng nào.
- SQL Server: script 23 chạy hai lần thành công; test script 23 PASS cả hai ca.
- Lệnh kiểm chứng: nạp `.env`, chạy `docker exec ... sqlcmd -b ... -i /dev/stdin < database/23_ingest_telemetry_batch.sql` hai lần, sau đó chạy cùng lệnh với `database/23_test_ingest_telemetry_batch.sql`.
- SP batch là bổ sung DB riêng; API REST và hợp đồng `docs/API.md` không đổi, API hiện tại vẫn ingest snapshot qua `usp_record_telemetry_wide`.

**Sprint UI redesign (2026-11-13):**
- `web/app/globals.css`: visual system sáng (nền `#f5f5f7`, card trắng, viền mảnh,
  shadow mềm), typography system font, bo góc 18–28px, hover/focus rõ ràng.
- Dashboard và `/scan` dùng chung token màu/typography; bỏ nền tối và font
  `DM Sans`/`Space Grotesk`/`DM Mono`.
- Motion: một nhịp `rise` khi panel xuất hiện; hover lift nhẹ trên button;
  `prefers-reduced-motion` tắt toàn bộ animation/transition.
- Responsive: 800px và 520px cho dashboard; 520px/380px cho trang scan.
- Giữ nguyên API contract, JWT, role check, polling 5 giây và toàn bộ SP.
- `cd web && npm exec -- tsc --noEmit` → PASS (không output).
- `npm run build` vẫn fail ở Turbopack/`powershell-utils` (blocker cũ, không do UI).

### Chưa có / còn thiếu
- SQL Login/User/Role/GRANT (phân quyền DB-level)
- Đo hiệu năng (index, partition, STATISTICS IO)
- Backup/restore có bằng chứng
- E2E demo evidence, báo cáo, video
- Production build cần xử lý Turbopack/PowerShell environment blocker
- Push `53fd62a` lên `origin/dev-hoangminh`

## Dữ liệu mẫu cục bộ (không commit vào git)

| Tài khoản | Mật khẩu demo | Ghi chú |
|---|---|---|
| admin | `demo123` | hash bcrypt seed ở script 09 |
| operator | `demo123` | — |
| technician | `demo123` | — |

Agent key demo (node 1): `arimms-demo-agent-key-2026`
(SHA-256 `749fc7b2…11c646bc`, seed ở script 09. Đổi trước khi dùng ngoài máy local.)

Lưu ý kết nối: SQL Server publish ra host port **1434** (`MSSQL_PORT` trong `.env`),
không phải 1433. `web/.env.local` phải đặt `DB_SERVER=127.0.0.1`, `DB_PORT=1434`.

## Lệnh kiểm chứng

```bash
# Áp DB scripts 11-14
set -a && . ./.env && set +a && export MSYS_NO_PATHCONV=1
docker exec -i ar-imms-sqlserver /opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i /dev/stdin < database/11_ticket_management.sql
docker exec -i ar-imms-sqlserver /opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i /dev/stdin < database/12_test_ticket_management.sql
docker exec -i ar-imms-sqlserver /opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i /dev/stdin < database/13_user_directory.sql
docker exec -i ar-imms-sqlserver /opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i /dev/stdin < database/14_test_user_directory.sql
```

```bash
# TypeScript (chạy trong web/)
cd web && npm exec -- tsc --noEmit
```

```bash
# E2E ticket lifecycle
TOKEN=$(curl -sS -X POST localhost:3000/api/auth/login -H 'Content-Type: application/json' -d '{"username":"operator","password":"demo123"}' | node -pe "JSON.parse(require('fs').readFileSync(0)).token")
curl -sS -X POST localhost:3000/api/tickets -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"node_id":1,"title":"CPU cao","description":"Kiểm tra tản nhiệt","priority":"HIGH"}'
curl -sS localhost:3000/api/tickets -H "Authorization: Bearer $TOKEN"
curl -sS localhost:3000/api/users/technicians -H "Authorization: Bearer $TOKEN"
curl -sS "localhost:3000/api/markers/AR-IMMS-NODE-1" -H "Authorization: Bearer $TOKEN"
```

```bash
# Kiểm tra audit log ticket
docker exec -i ar-imms-sqlserver /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d AR_IMMS -Q "SELECT action, COUNT(*) c FROM dbo.audit_logs WHERE target_entity=N'TICKET' GROUP BY action ORDER BY action;"
```

## Việc cần làm tiếp (backlog)

1. TypeScript check `cd web && npm exec -- tsc --noEmit`
2. SQL Login/GRANT, index/partition, backup/restore
3. Push commit lên `origin/dev-hoangminh`
4. E2E video demo, báo cáo cuối
