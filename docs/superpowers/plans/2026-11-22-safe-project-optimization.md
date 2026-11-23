# Safe AR-IMMS Project Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean the AR-IMMS repository structure and backend code while preserving SQL Server, stored-procedure-only business access, REST API behavior, and the existing migration order.

**Architecture:** First make documentation the source of truth, then introduce only low-risk backend cleanup around shared database-procedure calls, validation, and configuration. SQL files remain in their current locations during this pass; any later grouping is a separate migration-safe task.

**Tech Stack:** Flask, Flask-SQLAlchemy connection pool, pyodbc SQL Server driver, Next.js, Python unittest, SQL Server Developer, Docker Compose.

**Spec:** User request and approved direction in conversation; reference structure: `D:/Temp Downloads/AR-IMMS-main/AR-IMMS`.

## Global Constraints

- Database MUST remain SQL Server Developer; do not introduce PostgreSQL, SQLite, or ORM business queries.
- Backend business data access MUST call SQL Server stored procedures; SQLAlchemy is limited to connection/pool management and procedure execution.
- Preserve current REST API routes, request/response contracts, authentication behavior, and database object names.
- Do not delete migration, verification, benchmark, backup, or restore scripts.
- Do not commit secrets, `.env`, passwords, or keys.
- Run existing backend and frontend checks after each independently testable group.

## Review Focus

- Running without SQL Server: configuration errors must remain explicit and tests must not require a live database.
- Stored procedure failures: rollback and mapped HTTP responses must remain unchanged.
- Invalid telemetry values and oversized batches: validation must reject them before SQL execution.
- Existing import paths: module cleanup must not break `py backend/app.py` or unittest discovery.
- Documentation claims: “implemented” and “verified” must not be stated without a command or evidence.

---

### Task 1: Establish repository documentation source of truth

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Create: `database/README.md`
- Modify: `docs/README.md`
- Modify: `docs/CONVENTIONS.md`
- Modify: `docs/STATUS.md`

**Interfaces:**
- Produces one canonical onboarding path, one canonical database execution path, and explicit separation of implemented versus verified work.

- [ ] **Step 1: Inventory the current scripts, entry points, environment variables, and test commands.**
- [ ] **Step 2: Rewrite `README.md` for onboarding:** architecture, prerequisites, `.env`, SQL Server startup, migration order, backend, collector, web, health check, tests, troubleshooting, and links to deeper docs.
- [ ] **Step 3: Rewrite `CLAUDE.md` as development rules:** SQL Server-only, stored procedure boundary, naming, migration safety, testing, security, change approval, and status update rules.
- [ ] **Step 4: Create `database/README.md` grouping scripts conceptually without moving them:** core schema, verification, business/security, backup/restore, scale/benchmark, and unsafe reset scripts.
- [ ] **Step 5: Remove stale claims from `docs/CONVENTIONS.md` and qualify `docs/STATUS.md` claims with evidence/date and pending items.**
- [ ] **Step 6: Verify every referenced path exists and every command matches the repository.**

### Task 2: Centralize low-risk backend database procedure execution

**Files:**
- Create: `backend/db_gateway.py`
- Modify: `backend/app.py`
- Modify: `backend/auth.py`
- Modify: `backend/dashboard_api.py`
- Test: existing `backend/test_*.py` plus one focused test if a new behavior is introduced.

**Interfaces:**
- Produces `execute_procedure(statement: str, params: dict | None = None)` and `rows(statement: str, params: dict | None = None)` wrappers using the existing `db.session`; no SQL business logic is added.

- [ ] **Step 1: Identify duplicated procedure execution, row mapping, rollback, and error translation patterns.**
- [ ] **Step 2: Add the smallest gateway helpers with the exact existing transaction behavior.**
- [ ] **Step 3: Migrate only duplicated call sites that preserve identical SQL statements and parameters.**
- [ ] **Step 4: Run backend unittest discovery and compare route-level behavior.**

### Task 3: Separate application configuration from Flask route registration

**Files:**
- Create: `backend/config.py`
- Modify: `backend/app.py`
- Modify: `backend/auth.py` only if configuration access is duplicated.
- Test: existing backend tests.

**Interfaces:**
- Produces `load_database_config()` and `configure_app(app)` with no API behavior changes; `create_app()` remains the public application factory.

- [ ] **Step 1: Add tests for missing `DATABASE_URL` and preserved SQLAlchemy pool options.**
- [ ] **Step 2: Move only environment/configuration parsing into `config.py`.**
- [ ] **Step 3: Keep route definitions and blueprint registration behavior unchanged.**
- [ ] **Step 4: Run all backend tests and the health script where SQL Server is available.**

### Task 4: Add clean structural documentation and verification checklist

**Files:**
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/DATABASE-SPECIFICATION.md`
- Create: `docs/OPERATION-GUIDE.md`
- Create: `docs/TEST-PLAN-AND-REPORT.md`
- Create: `docs/USER-MANUAL.md`
- Modify: `docs/README.md`

**Interfaces:**
- Produces linked documentation modeled on the sample project but describing the actual SQL Server implementation.

- [ ] **Step 1: Document actual request/data flows and module responsibilities.**
- [ ] **Step 2: Document SQL Server schema layers, stored procedure boundary, backup/restore, jobs, partitioning, and permissions.**
- [ ] **Step 3: Document reproducible test commands and mark unavailable environment-dependent checks as pending rather than passing.**
- [ ] **Step 4: Document role-based user workflows without inventing features outside the current API/UI.**
- [ ] **Step 5: Verify all cross-document links.**

### Task 5: Final verification and cleanup review

**Files:**
- Modify only files proven necessary by verification.

- [ ] **Step 1: Run `py -m unittest discover -s backend -p "test_*.py"`.**
- [ ] **Step 2: Run collector tests and frontend type/test/build checks when dependencies and services are available.**
- [ ] **Step 3: Run `git diff --check` and inspect changed files for secrets, stale paths, and accidental API changes.**
- [ ] **Step 4: Report completed, skipped, and environment-dependent checks separately.**
