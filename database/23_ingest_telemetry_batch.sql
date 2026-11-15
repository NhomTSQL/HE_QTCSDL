-- AR-IMMS: HQTCSDL-24 normalized telemetry batch ingest.
-- Purpose: insert multiple metric rows atomically from one JSON array payload.
--          Shape validation happens before any write; metrics whose code is not in
--          dbo.metric_types produce no row, and the resulting count mismatch throws
--          inside the transaction so every row of the batch is rolled back.
-- Payload: [ {"metric_type":"cpu_usage_percent","value":42.5,"timestamp":"2026-11-15T12:00:00Z"} ]
-- Timestamps must be timezone-qualified ISO-8601 and are stored as UTC datetime2.
-- Test case: database/23_test_ingest_telemetry_batch.sql.
-- Requires database/01-09 and seed data. Safe to rerun.
USE AR_IMMS;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ingest_telemetry
    @node_id INT,
    @payload NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
            THROW 51226, N'Unknown node.', 1;
        IF @payload IS NULL OR ISJSON(@payload) <> 1 OR LEFT(LTRIM(@payload), 1) <> N'['
            THROW 51227, N'Payload must be a JSON array.', 1;

        DECLARE @items TABLE (
            ordinal INT NOT NULL PRIMARY KEY,
            element_type INT NOT NULL,
            metric_type NVARCHAR(50) NULL,
            metric_value FLOAT NULL,
            timestamp_text NVARCHAR(50) NULL,
            timestamp_offset DATETIMEOFFSET(7) NULL,
            measured_at DATETIME2(7) NULL
        );

        INSERT @items (ordinal, element_type, metric_type, metric_value,
                       timestamp_text, timestamp_offset, measured_at)
        SELECT CONVERT(INT, batch.[key]), batch.[type], parsed.metric_type,
               parsed.metric_value, parsed.timestamp_text, parsed.timestamp_offset,
               CONVERT(DATETIME2(7), SWITCHOFFSET(parsed.timestamp_offset, N'+00:00'))
        FROM OPENJSON(@payload) AS batch
        OUTER APPLY OPENJSON(batch.value) WITH (
            metric_type NVARCHAR(50) N'$.metric_type',
            metric_value FLOAT N'$.value',
            timestamp_text NVARCHAR(50) N'$.timestamp',
            timestamp_offset DATETIMEOFFSET(7) N'$.timestamp'
        ) AS parsed;

        IF NOT EXISTS (SELECT 1 FROM @items)
            THROW 51228, N'Payload must contain at least one metric.', 1;
        IF EXISTS (
            SELECT 1 FROM @items item
            WHERE item.element_type <> 5
               OR NULLIF(LTRIM(RTRIM(item.metric_type)), N'') IS NULL
               OR item.metric_value IS NULL
               OR item.timestamp_offset IS NULL
               OR NOT (
                    RIGHT(item.timestamp_text, 1) = N'Z'
                    OR RIGHT(item.timestamp_text, 6) LIKE N'[+-][0-9][0-9]:[0-9][0-9]'
               )
        )
            THROW 51229, N'Payload contains an invalid metric name, value, or timezone-qualified timestamp.', 1;

        DECLARE @expected BIGINT = (SELECT COUNT_BIG(*) FROM @items);

        INSERT dbo.telemetry_metrics (node_id, metric_type_id, value, timestamp)
        SELECT @node_id, metric.id, item.metric_value, item.measured_at
        FROM @items item
        JOIN dbo.metric_types metric ON metric.code = item.metric_type;
        DECLARE @inserted BIGINT = @@ROWCOUNT;

        -- An unknown metric code silently drops its row above; fail here so the whole
        -- batch rolls back instead of persisting a partial payload.
        IF @inserted <> @expected
            THROW 51224, N'Payload references an unknown metric type; the batch was rolled back.', 1;

        COMMIT TRANSACTION;
        SELECT @inserted AS inserted_count;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

PRINT N'=== 23_ingest_telemetry_batch: procedure ready ===';
GO
