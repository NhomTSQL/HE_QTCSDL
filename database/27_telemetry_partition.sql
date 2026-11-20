-- ============================================================================
-- AR-IMMS: Partition theo ngày + clustered index (timestamp, node_id) cho telemetry_metrics (HQTCSDL-36)
-- Mục tiêu: dữ liệu chia đúng partition theo ngày (UTC); truy vấn lọc theo ngày chỉ quét partition cần.
-- Nội dung:
--   1) Partition function pf_telemetry_day: RANGE RIGHT, DATETIME2(7), mỗi mốc là 00:00 UTC của một ngày
--      (cửa sổ ban đầu: 35 ngày trước đến 14 ngày sau ngày chạy). RIGHT nên 00:00:00 thuộc ngày mới.
--   2) Partition scheme ps_telemetry_day (tất cả partition trên filegroup PRIMARY).
--   3) Chuyển bảng sang partition trong 1 transaction:
--        - bỏ PK clustered cũ trên id, tạo clustered index CIX_telemetry_timestamp_node (timestamp, node_id);
--        - tạo lại PK dạng NONCLUSTERED (id, timestamp) trên cùng partition scheme
--          (PK phải chứa cột partition thì mới cùng partition; id là identity nên vẫn duy nhất trong thực tế);
--        - tạo lại 2 index không cụm IX_telemetry_node_time / IX_telemetry_metric_type_time theo partition;
--        - so sánh số dòng trước/sau, lệch thì ROLLBACK.
--   4) usp_extend_telemetry_partitions: thêm mốc cho các ngày sắp tới (SPLIT RANGE), chạy lại không thêm trùng.
--      Cần chạy định kỳ (hoặc gắn SQL Agent job), vì dữ liệu sau mốc cuối cùng dồn vào partition cuối.
--   5) Truy vấn kiểm tra (chụp ảnh): số dòng theo partition, danh sách index.
-- Chạy lại an toàn: kiểm tra tồn tại trước mỗi bước; đã partition thì bỏ qua phần chuyển đổi.
-- NÊN BACKUP trước khi chạy trên DB có dữ liệu quan trọng.
-- Thứ tự trong chuỗi dựng DB: chạy SAU 01..05 (và 16); chạy lại 02 hay 04 không phá cấu trúc partition.
-- ============================================================================
USE AR_IMMS;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ----------------------------------------------------------------------------
-- 1. Partition function theo ngày
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pf_telemetry_day')
BEGIN
    DECLARE @days_before INT = 35;   -- số ngày trước ngày chạy
    DECLARE @days_after  INT = 14;   -- số ngày sau ngày chạy
    DECLARE @start DATE = DATEADD(DAY, -@days_before, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @n INT = @days_before + @days_after + 1;
    DECLARE @i INT = 0;
    DECLARE @list NVARCHAR(MAX) = N'';
    DECLARE @sql NVARCHAR(MAX);

    WHILE @i < @n
    BEGIN
        SET @list = @list + CASE WHEN @i = 0 THEN N'' ELSE N', ' END
                  + N'N''' + CONVERT(NCHAR(10), DATEADD(DAY, @i, @start), 23) + N'''';
        SET @i += 1;
    END

    SET @sql = N'CREATE PARTITION FUNCTION pf_telemetry_day (DATETIME2(7)) AS RANGE RIGHT FOR VALUES ('
             + @list + N');';
    EXEC (@sql);
    PRINT N'SUCCESS: đã tạo partition function pf_telemetry_day.';
END
ELSE
    PRINT N'SKIP: pf_telemetry_day đã tồn tại.';
GO

-- ----------------------------------------------------------------------------
-- 2. Partition scheme
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'ps_telemetry_day')
BEGIN
    CREATE PARTITION SCHEME ps_telemetry_day
        AS PARTITION pf_telemetry_day ALL TO ([PRIMARY]);
    PRINT N'SUCCESS: đã tạo partition scheme ps_telemetry_day.';
END
ELSE
    PRINT N'SKIP: ps_telemetry_day đã tồn tại.';
GO

-- ----------------------------------------------------------------------------
-- 3. Chuyển telemetry_metrics sang partition theo ngày
-- ----------------------------------------------------------------------------
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.telemetry_metrics', N'U') IS NULL
    THROW 51060, N'Table dbo.telemetry_metrics does not exist; run 02_create_tables.sql first.', 1;

IF COL_LENGTH(N'dbo.telemetry_metrics', N'timestamp') IS NULL
    THROW 51065, N'Column dbo.telemetry_metrics.timestamp does not exist; ensure table schema uses timestamp.', 1;

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID(N'dbo.telemetry_metrics') AND name = N'CIX_telemetry_timestamp_node')
BEGIN
    PRINT N'SKIP: telemetry_metrics đã được partition (CIX_telemetry_timestamp_node tồn tại).';
END
ELSE
BEGIN
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE referenced_object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
        THROW 51061, N'A foreign key references dbo.telemetry_metrics; review it before changing the primary key.', 1;

    DECLARE @rows_before BIGINT = (SELECT COUNT_BIG(*) FROM dbo.telemetry_metrics);
    DECLARE @pk SYSNAME = (SELECT name FROM sys.key_constraints
                           WHERE parent_object_id = OBJECT_ID(N'dbo.telemetry_metrics') AND type = 'PK');
    DECLARE @drop_pk NVARCHAR(400);
    DECLARE @rows_after BIGINT;

    BEGIN TRANSACTION;

        -- 3.1 Bỏ PK clustered cũ (tên do SQL Server tự sinh)
        IF @pk IS NOT NULL
        BEGIN
            SET @drop_pk = N'ALTER TABLE dbo.telemetry_metrics DROP CONSTRAINT ' + QUOTENAME(@pk) + N';';
            EXEC (@drop_pk);
        END

        -- 3.2 Clustered index theo yêu cầu issue, nằm trên partition scheme theo ngày
        CREATE CLUSTERED INDEX CIX_telemetry_timestamp_node
            ON dbo.telemetry_metrics ([timestamp], node_id)
            ON ps_telemetry_day ([timestamp]);

        -- 3.3 PK không cụm, cùng partition (phải chứa cột partition)
        ALTER TABLE dbo.telemetry_metrics
            ADD CONSTRAINT PK_telemetry_metrics PRIMARY KEY NONCLUSTERED (id, [timestamp])
            ON ps_telemetry_day ([timestamp]);

        -- 3.4 Tạo lại các index không cụm theo partition
        DROP INDEX IF EXISTS IX_telemetry_node_time ON dbo.telemetry_metrics;
        CREATE NONCLUSTERED INDEX IX_telemetry_node_time
            ON dbo.telemetry_metrics (node_id, [timestamp] DESC)
            ON ps_telemetry_day ([timestamp]);

        DROP INDEX IF EXISTS IX_telemetry_metric_type_time ON dbo.telemetry_metrics;
        CREATE NONCLUSTERED INDEX IX_telemetry_metric_type_time
            ON dbo.telemetry_metrics (metric_type_id, [timestamp] DESC)
            ON ps_telemetry_day ([timestamp]);

        -- 3.5 Không được mất hay thêm dòng
        SET @rows_after = (SELECT COUNT_BIG(*) FROM dbo.telemetry_metrics);
        IF @rows_after <> @rows_before
            THROW 51062, N'Row count changed while repartitioning telemetry_metrics; transaction rolled back.', 1;

    COMMIT TRANSACTION;

    PRINT N'SUCCESS: telemetry_metrics đã partition theo ngày (' + CAST(@rows_after AS NVARCHAR(20)) + N' dòng).';
END
GO

-- ----------------------------------------------------------------------------
-- 4. Thêm mốc partition cho các ngày sắp tới (chạy định kỳ; chạy lại không thêm trùng)
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_extend_telemetry_partitions
    @days_ahead INT = 14
AS
BEGIN
    SET NOCOUNT ON;

    IF @days_ahead < 1 OR @days_ahead > 90
        THROW 51064, N'days_ahead must be between 1 and 90.', 1;

    IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pf_telemetry_day')
        THROW 51063, N'Partition function pf_telemetry_day does not exist; run 17_telemetry_partition.sql.', 1;

    DECLARE @target DATETIME2(7) = CAST(DATEADD(DAY, @days_ahead, CAST(SYSUTCDATETIME() AS DATE)) AS DATETIME2(7));
    DECLARE @last DATETIME2(7) = (
        SELECT MAX(CAST(prv.value AS DATETIME2(7)))
        FROM sys.partition_range_values AS prv
        JOIN sys.partition_functions AS pf ON pf.function_id = prv.function_id
        WHERE pf.name = N'pf_telemetry_day');
    DECLARE @added INT = 0;

    WHILE @last < @target
    BEGIN
        SET @last = DATEADD(DAY, 1, @last);
        ALTER PARTITION SCHEME ps_telemetry_day NEXT USED [PRIMARY];
        ALTER PARTITION FUNCTION pf_telemetry_day() SPLIT RANGE (@last);
        SET @added += 1;
    END

    SELECT @added AS boundaries_added, @last AS last_boundary_utc;
END;
GO

PRINT N'=== HQTCSDL-36: telemetry_metrics partition theo ngày đã sẵn sàng ===';
GO