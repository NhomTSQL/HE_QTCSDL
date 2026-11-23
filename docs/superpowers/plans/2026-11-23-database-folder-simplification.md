# AR-IMMS Database Folder Simplification Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SQL Server setup easier to find and run, while preserving the numbered scripts as legacy history and keeping every verification/benchmark/restore script available.

**Architecture:** Keep the actual T-SQL scripts as the authoritative installation history under `database/legacy/`; place verification scripts separately under `database/verification/`. Add one documented setup entrypoint in the existing `scripts/` directory that runs the deployable legacy scripts in the verified order, never reset, benchmark, or restore drills. Keep a short `database/README.md` as the database landing page.

**Tech Stack:** SQL Server Developer, existing T-SQL scripts, PowerShell/sqlcmd only if the current environment demonstrably supports it; no new dependency.

**Spec:** User direction in conversation: make database structure as close to the sample as practical, retain old scripts under a legacy location, and keep SQL Server. This plan deliberately does not merge or rewrite T-SQL bodies until the canonical runner is verified.

## Global Constraints

- SQL Server Developer remains the only database target.
- Preserve all 27 SQL script filenames and contents; do not delete the legacy set.
- Preserve deployment order: `01–05, 08–10, 12–14, 16–17, 19–20, 22–23, 25–26`.
- Reset (`00`), verification (`06,07,11,18`), benchmarks (`21,24`), and restore drill (`15`) must not run in the normal install path.
- Do not change REST API, schema, stored procedure names, or application behavior.
- Do not commit credentials, `.env`, backups, or user changes.

## Review Focus

- A setup run must stop at the first failed SQL batch and return non-zero.
- Rerunning canonical scripts must retain existing idempotent behavior and not reset user data.
- SQLCMD/connection errors must be explicit; no fallback to another database engine.
- Verification, benchmark, reset, and restore scripts must remain excluded from normal installation.
- All documentation and command paths must resolve after file moves.

---

### Task 1: Classify and relocate the SQL scripts

**Files:**
- Move deployment scripts into `database/legacy/` (19 scripts listed above).
- Move verification scripts into `database/verification/` (`06`, `07`, `11`, `18`).
- Move benchmarks into `database/verification/benchmarks/` (`21`, `24`).
- Move operational-only scripts into `database/verification/operations/` (`00`, `15`).
- Keep `database/README.md` and `database/MIGRATION_GUIDE_SQLSERVER.md` at root until references are migrated.
- Test: add a path/inventory check under `scripts/tests/` or a small Python unittest in existing tests.

- [ ] **Step 1: Add an inventory test asserting all 27 SQL script names exist once in their planned folders. Run it and observe failure before moving.**
- [ ] **Step 2: Move files without editing their contents.**
- [ ] **Step 3: Run inventory test and verify exact counts 19/4/2/2.**

### Task 2: Add a single install entrypoint

**Files:**
- Create: `scripts/setup-database.ps1`
- Modify: `database/MIGRATION_GUIDE_SQLSERVER.md`
- Test: `scripts/tests/Test-DatabaseScriptInventory.ps1` or equivalent, using only built-in PowerShell assertions.

**Interfaces:**
- `scripts/setup-database.ps1` runs only the 19 deployable scripts in the exact order above, requires an explicit SQL Server connection target/database credentials or reads documented local configuration, stops on first failure, and exits non-zero. It must not expose credentials in output.

- [ ] **Step 1: Verify whether `sqlcmd` is available in the target container/host and choose the existing supported invocation; do not install tools.**
- [ ] **Step 2: Write a failing inventory/command-contract test for script ordering and exclusion of reset/test/benchmark/restore scripts.**
- [ ] **Step 3: Implement the runner with fail-fast behavior and safe credential handling.**
- [ ] **Step 4: Run the contract test; perform a non-destructive dry-run/list mode if supported.**
- [ ] **Step 5: Run against SQL Server only if the configured service is already available; otherwise report as blocked, not PASS.**

### Task 3: Make the database landing docs concise and authoritative

**Files:**
- Rewrite: `database/README.md`
- Rewrite: `database/MIGRATION_GUIDE_SQLSERVER.md`
- Modify: `README.md`, `CLAUDE.md`, `docs/README.md`, `docs/DOCUMENTATION-GUIDE.md`, `docs/SETUP-WINDOWS.md`, `docs/ERD-DATA-DICTIONARY.md`, `docs/BACKUP-TEST-CASES.md`, `docs/STATUS.md`, `docs/DEMO.md`, `docs/SECURITY-REVIEW.md`, `docs/SCOPE-MOSCOW.md` where paths are referenced.

- [ ] **Step 1: Make the root database README the short map: one install command, canonical order source, folder meanings, destructive-script warning.**
- [ ] **Step 2: Make migration guide the detailed source of truth and remove duplicated script lists from setup docs.**
- [ ] **Step 3: Update active paths and retain old path references only in clearly labeled historical notes.**
- [ ] **Step 4: Verify all Markdown links and search for references to old paths.**

### Task 4: Final verification

- [ ] **Step 1: Run inventory/path tests and `git diff --check`.**
- [ ] **Step 2: Run SQL setup only when SQL Server is reachable; report blocked checks explicitly.**
- [ ] **Step 3: Confirm no changes to legacy SQL file contents by comparing hashes against the pre-move copies.**
- [ ] **Step 4: Report the final tree, setup command, passed checks, and environment-dependent checks.**
