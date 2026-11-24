# AR-IMMS — Infrastructure Monitoring & Maintenance System

![Python](https://img.shields.io/badge/Python-3.11%2B-3776AB)
![Flask](https://img.shields.io/badge/Backend-Flask-000000)
![Next.js](https://img.shields.io/badge/Web-Next.js-000000)
![SQL Server](https://img.shields.io/badge/Database-SQL%20Server%20Developer-CC2927)

AR-IMMS là hệ thống giám sát và bảo trì hạ tầng Data Center thử nghiệm. Hệ thống quản lý Digital Twin theo mô hình:

```text
Site → Room → Rack → Node → Container
```

Kiến trúc triển khai:

```text
Next.js dashboard/BFF → Flask REST API → Stored Procedures → SQL Server Developer
Python collector ──────HTTP + X-API-Key────> Flask REST API
```

## Mục lục

1. [Tính năng](#tính-năng)
2. [Cấu trúc dự án](#cấu-trúc-dự-án)
3. [Yêu cầu](#yêu-cầu)
4. [Cấu hình](#cấu-hình)
5. [Khởi động SQL Server](#khởi-động-sql-server)
6. [Chạy backend](#chạy-backend)
7. [Chạy collector](#chạy-collector)
8. [Chạy web](#chạy-web)
9. [Kiểm tra](#kiểm-tra)
10. [Tài liệu liên quan](#tài-liệu-liên-quan)

## Tính năng chính

### Digital Twin và telemetry

- Quản lý 5 cấp `Site → Room → Rack → Node → Container`.
- Collector thu thập host/container metrics, gửi đơn lẻ hoặc batch qua Flask.
- SQL Server xử lý transaction, trạng thái Node, alert và lưu lịch sử telemetry.

### Alert, ticket và bảo trì

- Alert threshold, chống cảnh báo trùng và heartbeat stale-node.
- Ticket lifecycle cho Operator và Field Technician: `OPEN → IN_PROGRESS → PENDING_CLOSURE → CLOSED`.
- Quản lý asset, warranty và maintenance history.

### Web, QR và analytics

- Next.js dashboard/BFF song ngữ EN/VI, SSE và fallback polling.
- Mobile Web QR/marker lookup với HUD telemetry; không phải ứng dụng AR native.
- PUE, capacity, telemetry trend, báo cáo phân cấp và CSV UTF-8 BOM.

### Security và vận hành database

- JWT/session, RBAC, MFA/recovery, collector API key và audit bất biến.
- SQL Server Agent, Full/Diff/Log backup, restore drill, partition, Columnstore và least-privilege login.

## Cấu trúc dự án

```text
AR-IMMS/
├── backend/       api/, core/, db/, tests/, tools/ và app.py entrypoint
├── collector/     psutil collector, retry/buffer và container telemetry
├── web/           Next.js UI/BFF
├── database/      canonical/, legacy/, verification/ (SQL Server scripts)
├── scripts/       health/compose smoke checks
├── docs/          kiến trúc, vận hành, test và user guide
├── compose.yaml   SQL Server Developer + Agent cho local
└── .env.example   mẫu biến môi trường, không chứa secret thật
```

## Yêu cầu

- Windows 10/11 hoặc môi trường tương đương.
- Docker Desktop và Docker Compose.
- Python 3.11+ và Microsoft ODBC Driver 18 for SQL Server.
- Node.js/npm cho dashboard.
- Git.

## Cấu hình

PowerShell tại thư mục gốc:

```powershell
Copy-Item .env.example .env
```

Tối thiểu cần cấu hình `DATABASE_URL`, `JWT_SECRET_KEY` và các secret được khai báo trong `.env.example`. Đặt mật khẩu demo cục bộ qua `AR_IMMS_DEV_PASSWORD` (tối thiểu 8 ký tự). Không commit `.env`.

Nếu mật khẩu có ký tự đặc biệt trong connection string, URL-encode giá trị đó. Xem [docs/SETUP-WINDOWS.md](docs/SETUP-WINDOWS.md) để biết cấu hình Windows đầy đủ.

## Khởi động SQL Server

```powershell
docker compose up -d sqlserver
docker compose ps
```

Đợi service báo healthy, sau đó chạy các script theo [database/README.md](database/README.md). Không chạy reset trên database đang dùng.

## Chạy backend

```powershell
py -m venv .venv
.venv\Scripts\Activate.ps1
py -m pip install -r backend/requirements.txt
py backend/app.py
```

Kiểm tra:

```powershell
Invoke-RestMethod http://localhost:5000/health
```

Kết quả thành công:

```json
{"status":"healthy","database":"connected"}
```

## Chạy collector

Trong terminal khác, sau khi database và backend đã sẵn sàng:

```powershell
py -m pip install -r collector/requirements.txt
py collector/agent.py
```

Cấu hình endpoint, API key, chu kỳ và batch theo [collector/.env.example](collector/.env.example) và hướng dẫn trong [docs/OPERATION-GUIDE.md](docs/OPERATION-GUIDE.md).

## Chạy web

```powershell
cd web
Copy-Item .env.example .env.local
npm ci
npm run dev
```

Mở <http://localhost:3000>. Next.js chỉ gọi Flask BFF/API; không kết nối SQL Server.

## Kiểm tra

### Backend

```powershell
py -m unittest discover -s backend/tests -t . -p "test_*.py" -v
```

### Collector

```powershell
py -m unittest discover -s collector/tests -v
```

### Frontend

```powershell
cd web
npm test
npx tsc --noEmit
npm run build
```

### Smoke checks

```powershell
.\scripts\test-health.ps1
.\scripts\test-compose.ps1
```

Các test cần SQL Server phải được ghi rõ là chưa kiểm chứng nếu service/schema chưa sẵn sàng; không đánh dấu PASS chỉ vì test import thành công.

## Tài liệu liên quan

| Nhu cầu | Tài liệu |
|---|---|
| Tìm đúng tài liệu theo nhiệm vụ | [DOCUMENTATION-GUIDE.md](docs/DOCUMENTATION-GUIDE.md) |
| Cài đặt Windows/ODBC/Docker | [SETUP-WINDOWS.md](docs/SETUP-WINDOWS.md) |
| Kiến trúc module và luồng dữ liệu | [ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Database, migration và quyền | [DATABASE-SPECIFICATION.md](docs/DATABASE-SPECIFICATION.md), [database/README.md](database/README.md) |
| Vận hành backup/restore/Agent | [OPERATION-GUIDE.md](docs/OPERATION-GUIDE.md), [BACKUP-TEST-CASES.md](docs/BACKUP-TEST-CASES.md) |
| Kế hoạch kiểm thử | [TEST-PLAN-AND-REPORT.md](docs/TEST-PLAN-AND-REPORT.md) |
| Kịch bản demo/vấn đáp | [DEMO.md](docs/DEMO.md) |
| Hướng dẫn người dùng | [USER-MANUAL.md](docs/USER-MANUAL.md) |
| Phạm vi và trạng thái | [SCOPE-MOSCOW.md](docs/SCOPE-MOSCOW.md), [STATUS.md](docs/STATUS.md) |

- [Mục lục tài liệu](docs/README.md)
- [Kiến trúc](docs/ARCHITECTURE.md)
- [Đặc tả database](docs/DATABASE-SPECIFICATION.md)
- [Hướng dẫn vận hành](docs/OPERATION-GUIDE.md)
- [Kế hoạch và báo cáo test](docs/TEST-PLAN-AND-REPORT.md)
- [Hướng dẫn người dùng](docs/USER-MANUAL.md)
- [Cài đặt Windows](docs/SETUP-WINDOWS.md)
- [Phạm vi MoSCoW](docs/SCOPE-MOSCOW.md)
- [Trạng thái có bằng chứng](docs/STATUS.md)

