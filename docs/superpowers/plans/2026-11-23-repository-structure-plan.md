# AR-IMMS Repository Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize AR-IMMS backend and database folders into responsibility-based groups modeled on the sample project, without changing runtime behavior or SQL Server/API contracts.

**Architecture:** Keep `backend/app.py` as a compatibility entrypoint and move implementation modules into `backend/api`, `backend/core`, `backend/db`, `backend/tests`, and `backend/tools`. Move SQL files into `database/migrations`, `tests`, `benchmarks`, and `operations`, while retaining migration filenames, logical order, and guide files at `database/` root.

**Tech Stack:** Python 3.12, Flask, SQLAlchemy/pyodbc for SQL Server procedure execution, Python unittest, T-SQL, PowerShell, Next.js.

**Spec:** `docs/superpowers/specs/2026-11-23-repository-structure-design.md`

## Global Constraints

- SQL Server Developer remains the sole project database; no PostgreSQL or SQLite replacement.
- Backend business database access remains through SQL Server Stored Procedures.
- Preserve `py backend/app.py`, `create_app`, existing REST API route/request/response/status contracts, SQL object names, and migration order.
- Keep numbered SQL filenames exactly unchanged; do not delete or merge migration, test, benchmark, reset, backup, or restore scripts.
- Keep `collector/`, `web/`, `scripts/`, and `backups/` top-level.
- Do not commit `.env`, credentials, keys, database backups, or generated caches.
- Report SQL Server-dependent checks as skipped/blocked when SQL Server is unavailable.

## Review Focus

- Direct execution from repository root must still start `backend/app.py` and expose `create_app`.
- Test imports after files move must work both with the documented discovery command and without SQL Server for isolated tests.
- T-SQL paths in setup, backup/restore, demo, and benchmark docs must resolve to the moved files.
- Normal migration order must exclude reset, verification, benchmarks, and restore drills.
- No stale imports or references should point to deleted flat backend modules or old SQL paths.

---

### Task 1: Establish backend package layout and compatibility entrypoint

**Files:**
- Create: `backend/__init__.py`, `backend/api/__init__.py`, `backend/core/__init__.py`, `backend/db/__init__.py`, `backend/tests/__init__.py`, `backend/tools/__init__.py`
- Move: `backend/auth.py` → `backend/api/auth.py`
- Move: `backend/dashboard_api.py` → `backend/api/dashboard.py`
- Move: `backend/config.py` and `backend/security.py` → `backend/core/`
- Move: `backend/extensions.py` → `backend/core/extensions.py`
- Move: `backend/db_gateway.py` → `backend/db/gateway.py`
- Modify: `backend/app.py`
- Test: `backend/tests/test_config.py`

**Interfaces:**
- `backend/app.py` keeps `create_app()` and exports current compatibility names used by existing callers/tests; implementation modules are package-qualified.

- [ ] **Step 1: Add a compatibility test for `from app import create_app` and missing `DATABASE_URL` via `PYTHONPATH=backend`. Observe the expected current behavior before moving modules.**
- [ ] **Step 2: Move modules and add package markers.**
- [ ] **Step 3: Update imports to `backend.api.*`, `backend.core.*`, and `backend.db.*` while retaining the direct script entrypoint.**
- [ ] **Step 4: Keep compatibility re-exports in `backend/app.py` for `db`, helpers, constants, and blueprints that current tests import.**
- [ ] **Step 5: Run the focused config/security import tests and `py -m compileall -q backend`.**

### Task 2: Move backend tests and tools

**Files:**
- Move: `backend/test_*.py` → `backend/tests/test_*.py`
- Move: `backend/load_test_ingest.py` → `backend/tools/load_test_ingest.py`
- Modify: test imports and `docs/TEST-PLAN-AND-REPORT.md`, `README.md`, `docs/SETUP-WINDOWS.md` where they name test commands.

**Interfaces:**
- Test modules import the public application factory from `backend.app` or compatibility shim; test discovery works from repository root.

- [ ] **Step 1: Update test imports and test command in a focused test change; verify intended discovery command before the file moves.**
- [ ] **Step 2: Move test/tool files and update load-test documentation/entry paths.**
- [ ] **Step 3: Run `py -m unittest discover -s backend/tests -p "test_*.py" -v`; SQL-dependent failures are separately recorded.**

### Task 3: Group database scripts by role

**Files:**
- Move migrations, preserving names:
  - `01`–`05`, `08`–`10`, `12`–`14`, `16`–`17`, `19`–`20`, `22`–`23`, `25`–`26` → `database/migrations/`
- Move tests:
  - `06`, `07`, `11`, `18` → `database/tests/`
- Move benchmarks:
  - `21`, `24` → `database/benchmarks/`
- Move operations:
  - `00_reset.sql`, `15_restore_disaster_recovery.sql` → `database/operations/`
- Modify: `database/MIGRATION_GUIDE_SQLSERVER.md`, `database/README.md`

**Interfaces:**
- Migration guide contains only deployable scripts, in existing logical order, using new paths. Tests/benchmarks/operations remain separately named and never appear as normal migration steps.

- [ ] **Step 1: Add a file-path classification test/check using the exact mapping above.**
- [ ] **Step 2: Move SQL files with filesystem-aware moves; do not edit SQL bodies.**
- [ ] **Step 3: Update migration guide and database README links and commands.**
- [ ] **Step 4: Verify every moved file exists exactly once and all original numbers/names are preserved.**

### Task 4: Update all references and operational documentation

**Files:**
- Modify: `README.md`, `CLAUDE.md`, `collector/README.md`, `docs/*.md`, `scripts/*.ps1`, backend tests/tools and SQL comments that refer to old paths.

**Interfaces:**
- All active docs/commands reference the new paths; historical design notes may mention old paths only when explicitly labeled historical.

- [ ] **Step 1: Search repository for old backend module imports/paths and `database/<number>_*.sql` references.**
- [ ] **Step 2: Update installation, restore, demo, load-test, scope, ERD, backup, status, and test documents.**
- [ ] **Step 3: Run an automated relative-Markdown-link/path check and confirm zero broken links.**
- [ ] **Step 4: Verify README, Windows setup, and migration guide agree on migration order.**

### Task 5: Full verification

**Files:**
- Modify only files needed to fix verified path/import issues.

- [ ] **Step 1: Run focused backend tests and `py -m compileall -q backend`.**
- [ ] **Step 2: Run `py -m unittest discover -s backend/tests -p "test_*.py" -v`; report SQL Server connection/schema blockers without masking them.**
- [ ] **Step 3: Run `py -m unittest discover -s collector/tests -v`.**
- [ ] **Step 4: Run frontend tests/typecheck/build only if dependencies are installed; do not install packages without approval.**
- [ ] **Step 5: Run SQL Server migration/verifier checks only if the configured SQL Server is reachable.**
- [ ] **Step 6: Run `git diff --check`, inspect status, verify no secrets/caches were added, and report all skipped checks.**
