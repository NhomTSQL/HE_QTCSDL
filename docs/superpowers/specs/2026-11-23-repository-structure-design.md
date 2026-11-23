# AR-IMMS Repository Structure Design

## Intent

Tổ chức lại repository AR-IMMS gọn và dễ giải thích hơn, gần cấu trúc dự án mẫu `AR-IMMS-main/AR-IMMS`, nhưng giữ đúng đặc thù đồ án: SQL Server Developer là database duy nhất và backend chỉ truy cập nghiệp vụ qua Stored Procedure.

Mục tiêu là để ba nhóm người có thể tìm đúng nơi:

- thành viên mới cần chạy dự án;
- thành viên cần sửa backend/database;
- giảng viên cần kiểm tra schema, test, backup/restore và bằng chứng.

## Goals

- Nhóm backend theo trách nhiệm: `api`, `core`, `db`, `tests`, `tools`.
- Nhóm script SQL theo mục đích: `migrations`, `tests`, `benchmarks`, `operations`.
- Giữ các lệnh chạy quen thuộc: `py backend/app.py`, test discovery và các đường dẫn docs sau khi cập nhật.
- Giữ nguyên tên/nội dung/thứ tự logic của migration SQL.
- Giữ nguyên REST API routes, request/response/status code, stored procedure names và schema SQL Server.
- Loại bỏ cache Python khỏi repository working tree và tránh tạo lại bằng `.gitignore`.

## Non-goals

- Không đổi SQL Server sang PostgreSQL, SQLite hoặc database khác.
- Không chuyển backend sang ORM business query.
- Không rewrite API, frontend hoặc collector.
- Không đổi tên bảng/procedure/trigger/function/view.
- Không gộp nhiều migration thành một file mới.
- Không xóa script reset, test, benchmark, backup hoặc restore; chỉ di chuyển và phân loại.

## Anti-goals

- Không để hai chuỗi migration song song.
- Không sửa nội dung SQL chỉ vì di chuyển file.
- Không thay đổi behavior để làm import “đẹp” hơn.
- Không đánh dấu kiểm thử PASS nếu SQL Server/service chưa thực sự chạy.

## Target structure

```text
AR-IMMS/
├── README.md
├── CLAUDE.md
├── compose.yaml
├── .env.example
├── backend/
│   ├── app.py                    # compatibility entrypoint + create_app()
│   ├── requirements.txt
│   ├── api/
│   │   ├── auth.py               # auth blueprint and auth use-cases
│   │   └── dashboard.py          # dashboard blueprint and API routes
│   ├── core/
│   │   ├── config.py
│   │   ├── extensions.py
│   │   └── security.py
│   ├── db/
│   │   └── gateway.py            # stored-procedure execution helpers
│   ├── tests/
│   │   ├── test_auth_api.py
│   │   ├── test_config.py
│   │   ├── test_dashboard_api.py
│   │   ├── test_db_gateway.py
│   │   ├── test_security_regressions.py
│   │   └── test_telemetry_api.py
│   └── tools/
│       └── load_test_ingest.py
├── collector/
├── web/
├── database/
│   ├── migrations/
│   │   ├── 01_create_database.sql
│   │   ├── 02_create_tables.sql
│   │   ├── 03_seed_data.sql
│   │   ├── 04_procedures_triggers_views.sql
│   │   ├── 05_retention_policy.sql
│   │   ├── 08_dev_node_api_key.sql
│   │   ├── 09_auth_procedures.sql
│   │   ├── 10_agent_job_heartbeat.sql
│   │   ├── 12_backup_recovery_model.sql
│   │   ├── 13_backup_jobs.sql
│   │   ├── 14_backup_cleanup.sql
│   │   ├── 16_alert_dedupe.sql
│   │   ├── 17_dashboard_api_procedures.sql
│   │   ├── 19_security_and_core_fixes.sql
│   │   ├── 20_extended_features_procedures.sql
│   │   ├── 22_scale_architecture.sql
│   │   ├── 23_least_privilege_login.sql
│   │   ├── 25_password_recovery.sql
│   │   └── 26_security_hardening.sql
│   ├── tests/
│   │   ├── 06_verify_seed_data.sql
│   │   ├── 07_test_normalized_schema.sql
│   │   ├── 11_test_heartbeat_job.sql
│   │   └── 18_test_retention_batch.sql
│   ├── benchmarks/
│   │   ├── 21_performance_benchmark.sql
│   │   └── 24_scale_benchmark_1m.sql
│   ├── operations/
│   │   ├── 00_reset.sql
│   │   └── 15_restore_disaster_recovery.sql
│   ├── MIGRATION_GUIDE_SQLSERVER.md
│   └── README.md
├── docs/
└── scripts/
```

`database/README.md` and `MIGRATION_GUIDE_SQLSERVER.md` remain at the database root so they are easy to find. The numbered SQL files move only into category folders; their numeric names and relative order do not change.

## Compatibility rules

### Backend

- `backend/app.py` remains executable directly and continues exporting `create_app`.
- `backend/app.py` adds compatibility imports/re-exports only where existing tests or scripts need them (`db`, helper functions, constants); no new API behavior.
- Internal imports become package-qualified or stable relative imports according to the chosen entrypoint strategy. Test discovery will run from repository root with an explicit `PYTHONPATH=backend` or an equivalent documented command.
- `backend/tests/` is the only location for backend tests after the move.

### Database

- Every moved SQL file keeps its contents byte-for-byte unless a path comment must be corrected.
- Migration guide lists `database/migrations/<file>` paths in the original logical order.
- Test/benchmark/operation scripts are never included in the normal migration list.
- All docs, test fixtures, comments and scripts referring to old paths are updated.

### Other modules

- `collector/`, `web/`, `scripts/` and `backups/` remain top-level because they are independently runnable modules/assets.
- No `node_modules`, `.venv`, `__pycache__` or generated build output is moved into source folders.

## Migration sequence

1. Add package markers and compatibility imports without moving behavior.
2. Move backend modules one responsibility group at a time; run focused tests after each group.
3. Move backend tests/tools and update documented test commands.
4. Create database category directories and move SQL files with filesystem-aware commands.
5. Update migration guide, README, docs and comments to new paths.
6. Run link/path checks, Python compile, backend/collector tests, frontend checks when dependencies exist, and SQL Server checks when service is available.
7. Compare API route list and import entrypoint before/after.

## Verification contract

The change is complete only if:

- `py backend/app.py` still starts far enough to validate configuration.
- backend focused tests pass without SQL Server where they are designed not to need it;
- collector tests pass;
- all Markdown relative links resolve;
- no old `database/<number>_*.sql` paths remain outside migration history/spec notes;
- no direct import references point to deleted backend paths;
- `git diff --check` passes;
- SQL Server migration/test/restore checks are reported as PASS, FAIL or SKIPPED based on actual availability.

## Builder decisions

- Keep `app.py` as a thin compatibility entrypoint instead of renaming it to `src/app.py`; this minimizes deployment and documentation risk.
- Use `backend/api`, `backend/core`, and `backend/db` rather than a larger domain/infrastructure split; the current backend is small and SQL Server procedure-centric, so additional layers would add indirection without value.
- Keep numbered filenames rather than renumbering; numbers are part of the migration contract.
- Put reset/restore in `database/operations`; reset is intentionally not part of deployment and restore is an operational drill.
