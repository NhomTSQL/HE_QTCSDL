-- ============================================================================
-- AR-IMMS: Performance Benchmark cho Time-Series Telemetry
-- Kiểm chứng tốc độ truy vấn snapshot (vw_latest_telemetry) và lịch sử
-- (usp_get_telemetry_history) trên tập dữ liệu 50,000 dòng với Covering Index
-- IX_telemetry_node_metric_time_inc.
-- An toàn: bọc trong TRANSACTION và ROLLBACK sau khi đo, không làm bẩn DB.
-- ============================================================================

USE AR_IMMS;
GO
SET NOCOUNT ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_telemetry_node_metric_time_inc'
      AND object_id = OBJECT_ID(N'dbo.telemetry_metrics')
)
    THROW 51095, N'Missing covering index IX_telemetry_node_metric_time_inc. Run script 19 first.', 1;
GO

BEGIN TRANSACTION;

;WITH nums AS (
    SELECT TOP (50000)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.telemetry_metrics (node_id, metric_type_id, value, timestamp)
SELECT ((rn - 1) % 4) + 1 AS node_id,
       (((rn - 1) / 4) % 4) + 1 AS metric_type_id,
       CAST(20.0 + ((rn % 65) * 1.0) AS FLOAT) AS value,
       DATEADD(SECOND, -(rn % 86400), SYSUTCDATETIME()) AS timestamp
FROM nums
WHERE EXISTS (SELECT 1 FROM dbo.nodes WHERE id = ((rn - 1) % 4) + 1)
  AND EXISTS (SELECT 1 FROM dbo.metric_types WHERE id = (((rn - 1) / 4) % 4) + 1);

DECLARE @row_count BIGINT = (SELECT COUNT_BIG(*) FROM dbo.telemetry_metrics);
PRINT N'Benchmark dataset rows in transaction: ' + CAST(@row_count AS NVARCHAR(20));

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT node_id, metric_type, value, unit, timestamp
FROM dbo.vw_latest_telemetry;

EXEC dbo.usp_get_telemetry_history
    @node_id = 1,
    @metric_type = N'cpu_usage_percent',
    @limit = 40;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

ROLLBACK TRANSACTION;
GO

PRINT N'PASS: Benchmark completed and rolled back cleanly.';
GO
