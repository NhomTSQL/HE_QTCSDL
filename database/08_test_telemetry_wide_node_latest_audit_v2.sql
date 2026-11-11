-- Run after database/08_telemetry_wide_node_latest_audit_v2.sql.
-- All writes are rolled back; expected result is PASS.
USE AR_IMMS;
GO

SET NOCOUNT ON;

IF COL_LENGTH(N'dbo.telemetry_wide', N'telemetry_id') IS NULL
   OR EXISTS (
       SELECT 1 FROM sys.columns
       WHERE object_id = OBJECT_ID(N'dbo.telemetry_wide')
         AND name = N'telemetry_id'
         AND system_type_id <> 127
   )
    THROW 51060, N'telemetry_wide must use a BIGINT telemetry_id key.', 1;

IF COL_LENGTH(N'dbo.telemetry_wide', N'collected_at') IS NULL
    THROW 51061, N'telemetry_wide must have collected_at.', 1;
IF OBJECT_ID(N'dbo.node_latest', N'U') IS NULL
    THROW 51062, N'node_latest table is missing.', 1;
IF COL_LENGTH(N'dbo.audit_logs', N'event_id') IS NULL
   OR COL_LENGTH(N'dbo.audit_logs', N'event_type') IS NULL
   OR COL_LENGTH(N'dbo.audit_logs', N'created_at') IS NULL
    THROW 51063, N'audit_logs v2 columns are missing.', 1;

DECLARE @before BIGINT = (SELECT COUNT_BIG(*) FROM dbo.telemetry_wide);
DECLARE @collected_at DATETIME2(0) = CONVERT(DATETIME2(0), SYSUTCDATETIME());

BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.usp_record_telemetry_wide
        @node_id = 1,
        @collected_at = @collected_at,
        @cpu_usage_percent = 42.50,
        @memory_usage_percent = 64.25,
        @disk_usage_percent = 70.00,
        @temperature_celsius = 50.00;

    IF (SELECT COUNT_BIG(*) FROM dbo.telemetry_wide) <> @before + 1
        THROW 51064, N'Expected one wide telemetry row.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.node_latest
        WHERE node_id = 1 AND collected_at = @collected_at
          AND cpu_usage_percent = 42.50
    )
        THROW 51065, N'Expected node_latest to contain the newest snapshot.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.audit_logs
        WHERE action = N'TELEMETRY_WIDE_RECORDED'
          AND target_entity = N'NODE' AND target_id = N'1'
          AND event_id IS NOT NULL AND created_at IS NOT NULL
    )
        THROW 51066, N'Expected v2 audit metadata for the snapshot.', 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

PRINT N'PASS: wide telemetry, node_latest and audit_logs v2 are valid.';
GO
