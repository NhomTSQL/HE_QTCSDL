-- AR-IMMS: HQTCSDL-24 batch telemetry regression tests.
-- Requires database/01-09, 23_ingest_telemetry_batch.sql and seed data.
-- Non-destructive: each test rolls back its transaction.
USE AR_IMMS;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @node_id INT = (SELECT TOP (1) id FROM dbo.nodes ORDER BY id);
IF @node_id IS NULL THROW 51220, N'No seeded node is available for batch ingest tests.', 1;

-- Test 1: one call writes multiple normalized metrics atomically.
DECLARE @before BIGINT;
SELECT @before = COUNT_BIG(*) FROM dbo.telemetry_metrics WHERE node_id = @node_id;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.usp_ingest_telemetry
        @node_id = @node_id,
        @payload = N'[
          {"metric_type":"cpu_usage_percent","value":42.5,"timestamp":"2026-11-15T12:00:00Z"},
          {"metric_type":"memory_usage_percent","value":51.25,"timestamp":"2026-11-15T12:00:01Z"},
          {"metric_type":"temperature_celsius","value":48.0,"timestamp":"2026-11-15T12:00:02Z"}
        ]';

    IF (SELECT COUNT_BIG(*) FROM dbo.telemetry_metrics WHERE node_id = @node_id) <> @before + 3
        THROW 51221, N'Batch ingest did not insert exactly three metrics.', 1;
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.telemetry_metrics telemetry
        JOIN dbo.metric_types metric ON metric.id = telemetry.metric_type_id
        WHERE telemetry.node_id = @node_id
          AND metric.code = N'cpu_usage_percent'
          AND telemetry.value = 42.5
          AND telemetry.timestamp = CONVERT(DATETIME2, '2026-11-15T12:00:00')
    )
        THROW 51222, N'Batch ingest CPU metric was not stored correctly.', 1;

    PRINT N'[PASS] Batch ingest writes multiple normalized metrics in one call.';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- Test 2: a later invalid metric rolls back earlier rows from the same batch.
-- Runs outside an open transaction because the procedure sets XACT_ABORT ON and
-- rolls back on THROW, which would doom an ambient transaction.
DECLARE @node_id2 INT = (SELECT TOP (1) id FROM dbo.nodes ORDER BY id);
IF @node_id2 IS NULL THROW 51220, N'No seeded node is available for batch ingest tests.', 1;
DECLARE @before2 BIGINT;
SELECT @before2 = COUNT_BIG(*) FROM dbo.telemetry_metrics WHERE node_id = @node_id2;
BEGIN TRY
    EXEC dbo.usp_ingest_telemetry
        @node_id = @node_id2,
        @payload = N'[
          {"metric_type":"cpu_usage_percent","value":43.5,"timestamp":"2026-11-15T12:01:00Z"},
          {"metric_type":"metric_does_not_exist","value":1.0,"timestamp":"2026-11-15T12:01:01Z"}
        ]';
    THROW 51223, N'Invalid metric type was accepted.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51223 THROW;
    IF ERROR_NUMBER() <> 51224 THROW;
    IF (SELECT COUNT_BIG(*) FROM dbo.telemetry_metrics WHERE node_id = @node_id2) <> @before2
        THROW 51225, N'Batch rollback left an earlier metric row behind.', 1;
    PRINT N'[PASS] Invalid metric rolls back the complete batch.';
END CATCH;
GO

PRINT N'=== HQTCSDL-24 batch telemetry tests complete ===';
GO
