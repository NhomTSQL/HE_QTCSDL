-- Regression check for the batch-count pattern in usp_cleanup_old_telemetry.
-- Safe: uses only a local temp table; no AR_IMMS rows are touched.
SET NOCOUNT ON;

CREATE TABLE #retention_test (id INT IDENTITY(1,1) PRIMARY KEY);
GO
INSERT INTO #retention_test DEFAULT VALUES;
GO 25000

DECLARE @deleted_count INT = 0;
DECLARE @batch_count INT = 0;

WHILE 1 = 1
BEGIN
    DELETE TOP (10000) FROM #retention_test;

    SET @batch_count = @@ROWCOUNT;
    SET @deleted_count += @batch_count;

    IF @batch_count < 10000 BREAK;
END;

IF @deleted_count <> 25000 OR EXISTS (SELECT 1 FROM #retention_test)
    THROW 51080, N'Retention batch regression test failed.', 1;

SELECT @deleted_count AS rows_deleted,
       (SELECT COUNT(*) FROM #retention_test) AS remaining_rows;
-- Expected: rows_deleted = 25000, remaining_rows = 0.
