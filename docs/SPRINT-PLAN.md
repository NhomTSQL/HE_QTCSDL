# Kế hoạch sprint AR-IMMS

Khung thời gian: 11/11 → 02/12/2026 (3 tuần). Kanban, không có sprint cứng.
Mốc theo tuần là checkpoint kiểm tra, không phải batch việc bắt buộc.

## Lịch tổng

| Thời gian | Mục tiêu | Bằng chứng nghiệm thu |
|---|---|---|
| **11–12/11** | Dọn repo, hợp đồng, lát cắt dọc: collector → SP → node_latest → web hiện số | `curl POST /api/telemetry` → 201; `curl GET /api/nodes` trả CPU sống |
| **13–17/11** | Ticket + vòng đời + closure request, audit log qua trigger, trang web quét QR | Demo đủ kịch bản DEMO.md từ bước 1–4 |
| **18–24/11** | SQL Login/Role/GRANT tối thiểu; đo hiệu năng index/partition (STATISTICS IO + execution plan trước/sau); backup Full/Diff/Log + 1 lần restore thật | File `docs/EVIDENCE-SECURITY.md`, `docs/EVIDENCE-PERFORMANCE.md`, `docs/EVIDENCE-BACKUP.md` có số đo thật |
| **25–30/11** | Đóng băng tính năng, test end-to-end theo DEMO.md, báo cáo, video demo dự phòng | Checklist DEMO.md chạy được đầu-cuối; báo cáo nháp |
| **01–02/12** | Tập vấn đáp, chỉ sửa lỗi | — |

## Nguyên tắc
- Từ 25/11: **không thêm tính năng mới**. Chỉ sửa lỗi và viết tài liệu.
- Mỗi chiều: tự chạy lại kịch bản demo, không chỉ tin báo cáo của agent.
- Mỗi SP/trigger agent viết: đọc lại và tự giải thích được để vấn đáp.

## Phân công agent AI

| Agent | Thư mục | Nhánh | Nhiệm vụ hiện tại |
|---|---|---|---|
| DB | `database/` | `agent/db` | Script 09 (đổi tên usp_), usp_record_telemetry_wide có alert, usp_authenticate_* , seed hash thật |
| Web+API | `web/` | `agent/web` | Next.js init, callSp() bằng mssql, POST /api/telemetry, POST /api/auth/login, GET /api/nodes |
| Collector | `collector/` | `agent/collector` | Python psutil gửi mỗi 5 giây, retry, buffer |

## Worktree commands
```powershell
git worktree add ..\HE_QTCSDL-db        -b agent/db
git worktree add ..\HE_QTCSDL-web       -b agent/web
git worktree add ..\HE_QTCSDL-collector -b agent/collector
```
