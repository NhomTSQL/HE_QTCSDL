# SDD ledger — plan: docs/superpowers/plans/2026-11-23-database-folder-simplification.md

Task 1: blocked before filesystem changes — shell tools were denied by the environment safety classifier while creating `database/legacy`, `database/canonical`, and copying SQL files. No SQL files were moved or modified.
Task 2: not started — depends on the legacy/canonical path decision and executable filesystem operations.
Task 3: not started — existing docs remain unchanged for this plan.
Task 4: not started.

Ruling: preserve the original checkout and do not emulate file moves with new duplicate SQL content while shell operations are blocked. Cost if wrong: progress pauses until filesystem permissions recover; avoids corrupting or duplicating the 27-script SQL set.
