-- ============================================================================
-- AR-IMMS: 1,000,000-Row Scale Benchmark (Before vs After Optimization)
-- Đo kiểm so sánh trực tiếp:
--   1. Legacy ROW_NUMBER() trên 1,000,000 dòng vs Snapshot O(1) (vw_latest_telemetry)
--   2. Rowstore Scan vs Nonclustered Columnstore Index (NCCI_telemetry_analytics)
--   3. Partition Pruning qua 4 phân vùng tháng trên PS_TelemetryMonth
-- An toàn: bọc trong TRANSACTION và ROLLBACK sau khi đo để DB không phình dung lượng.
-- ============================================================================

USE AR_IMMS;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

BEGIN TRANSACTION;

;WITH base AS (
    SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
),
nums AS (
    SELECT TOP (1000000)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM base a
    CROSS JOIN base b
)
INSERT INTO dbo.telemetry_metrics (node_id, metric_type_id, value, timestamp)
SELECT ((rn - 1) % 4) + 1 AS node_id,
       (((rn - 1) / 4) % 4) + 1 AS metric_type_id,
       CAST(20.0 + ((rn % 70) * 1.0) AS FLOAT) AS value,
       CASE (rn % 4)
           WHEN 0 THEN DATEADD(SECOND, -(rn % 86400), '2026-08-15T12:00:00')
           WHEN 1 THEN DATEADD(SECOND, -(rn % 86400), '2026-09-15T12:00:00')
           WHEN 2 THEN DATEADD(SECOND, -(rn % 86400), '2026-10-15T12:00:00')
           ELSE        DATEADD(SECOND, -(rn % 86400), '2026-11-15T12:00:00')
       END AS timestamp
FROM nums;

SELECT COUNT_BIG(*) AS total_benchmark_rows FROM dbo.telemetry_metrics;

-- Phân bố dữ liệu trên các partition của PS_TelemetryMonth
SELECT $PARTITION.PF_TelemetryMonth(timestamp) AS partition_num,
       COUNT_BIG(*) AS rows_in_partition,
       MIN(timestamp) AS min_ts,
       MAX(timestamp) AS max_ts
FROM dbo.telemetry_metrics
GROUP BY $PARTITION.PF_TelemetryMonth(timestamp)
ORDER BY partition_num;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT N'--- [1A] BEFORE: Legacy ROW_NUMBER() over 1M rows ---';
;WITH LegacyRanked AS (
    SELECT tm.node_id, mt.code AS metric_type, tm.value, mt.unit, tm.timestamp,
           ROW_NUMBER() OVER (PARTITION BY tm.node_id, tm.metric_type_id ORDER BY tm.timestamp DESC) AS rn
    FROM dbo.telemetry_metrics tm
    INNER JOIN dbo.metric_types mt ON mt.id = tm.metric_type_id
)
SELECT node_id, metric_type, value, unit, timestamp
FROM LegacyRanked
WHERE rn = 1
OPTION (IGNORE_NONCLUSTERED_COLUMNSTORE_INDEX);

PRINT N'--- [1B] AFTER: O(1) Snapshot view (dbo.node_latest_metrics) ---';
SELECT node_id, metric_type, value, unit, timestamp
FROM dbo.vw_latest_telemetry;

PRINT N'--- [2A] BEFORE: Full Analytics Aggregation (Rowstore) ---';
SELECT node_id, metric_type_id,
       AVG(value) AS avg_val, MAX(value) AS max_val, COUNT_BIG(*) AS samples
FROM dbo.telemetry_metrics
GROUP BY node_id, metric_type_id
OPTION (IGNORE_NONCLUSTERED_COLUMNSTORE_INDEX);

PRINT N'--- [2B] AFTER: Full Analytics Aggregation (Columnstore NCCI) ---';
SELECT node_id, metric_type_id,
       AVG(value) AS avg_val, MAX(value) AS max_val, COUNT_BIG(*) AS samples
FROM dbo.telemetry_metrics
GROUP BY node_id, metric_type_id;

PRINT N'--- [3] Partition Pruning Query (1 Month Slice: 2026-10) ---';
SELECT node_id, AVG(value) AS avg_oct, COUNT_BIG(*) AS oct_samples
FROM dbo.telemetry_metrics
WHERE timestamp >= '2026-10-01' AND timestamp < '2026-11-01'
GROUP BY node_id;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

ROLLBACK TRANSACTION;
GO

PRINT N'PASS: 1,000,000-row benchmark completed and rolled back cleanly.';
GO
