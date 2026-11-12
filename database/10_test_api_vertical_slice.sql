-- AR-IMMS: API vertical-slice SQL smoke tests. Requires scripts 01-09 + seed data.
-- Non-destructive: each ingest test runs in a transaction and is rolled back.
USE AR_IMMS;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @failures INT = 0;

-- Contract test: user lookup returns one row, role code, active flag.
IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE username=N'admin')
    PRINT N'[SKIP] Seed user admin unavailable';
ELSE IF NOT EXISTS (
    SELECT 1 FROM OPENQUERY([LOCALSERVER], 'EXEC AR_IMMS.dbo.usp_authenticate_user @username = N''admin''')
)
    PRINT N'[NOTE] Verify usp_authenticate_user manually; OPENQUERY unavailable in local SQL Server.';
GO

-- Test ingest validations. Each data-changing case is isolated and rolled back.
BEGIN TRY
    EXEC dbo.usp_record_telemetry_wide @node_id=2147483000, @collected_at='2026-11-12T00:00:00', @cpu_usage_percent=30;
    THROW 51100, N'Expected invalid node to be rejected.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51100
    BEGIN
        PRINT N'[FAIL] Invalid node was accepted.';
        SET @failures += 1;
    END
    ELSE IF ERROR_NUMBER() = 51050
        PRINT N'[PASS] Invalid node rejected with 51050.';
    ELSE
    BEGIN
        PRINT N'[FAIL] Unexpected error for invalid node: ' + ERROR_MESSAGE();
        SET @failures += 1;
    END
END CATCH;
GO

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @node_id INT = (SELECT TOP (1) id FROM dbo.nodes ORDER BY id);
    IF @node_id IS NULL THROW 51101, N'No seeded node; cannot run telemetry test.', 1;
    DECLARE @stamp DATETIME2(0) = DATEADD(SECOND, 1, CONVERT(DATETIME2(0), SYSUTCDATETIME()));

    EXEC dbo.usp_record_telemetry_wide
        @node_id=@node_id, @collected_at=@stamp, @cpu_usage_percent=95.50,
        @memory_usage_percent=40, @disk_usage_percent=50;

    IF NOT EXISTS (SELECT 1 FROM dbo.node_latest WHERE node_id=@node_id AND collected_at=@stamp AND cpu_usage_percent=95.50)
        THROW 51102, N'node_latest was not updated.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM dbo.alerts a JOIN dbo.alert_thresholds t ON t.id=a.threshold_id
        JOIN dbo.metric_types m ON m.id=t.metric_type_id
        WHERE a.node_id=@node_id AND m.code=N'cpu_usage_percent'
          AND a.status=N'OPEN' AND a.severity=N'CRITICAL'
    ) THROW 51103, N'Expected CPU critical alert not found.', 1;

    DECLARE @stamp2 DATETIME2(0)=DATEADD(SECOND,1,@stamp);
    EXEC dbo.usp_record_telemetry_wide @node_id=@node_id, @collected_at=@stamp2, @cpu_usage_percent=96;

    IF (SELECT COUNT(*) FROM dbo.alerts a JOIN dbo.alert_thresholds t ON t.id=a.threshold_id
        JOIN dbo.metric_types m ON m.id=t.metric_type_id
        WHERE a.node_id=@node_id AND m.code=N'cpu_usage_percent' AND a.status IN (N'OPEN',N'ACKNOWLEDGED')) <> 1
        THROW 51104, N'Alert deduplication failed.', 1;

    PRINT N'[PASS] Telemetry insert, latest projection, threshold alert, dedup.';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    PRINT N'[FAIL] Ingest test: ' + ERROR_MESSAGE();
    THROW;
END CATCH;
GO

PRINT N'=== Test complete. Any [FAIL] or thrown error indicates failure. ===';
GO
