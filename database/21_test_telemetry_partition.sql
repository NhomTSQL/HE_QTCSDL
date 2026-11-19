-- ============================================================================
-- AR-IMMS: Test partition telemetry_metrics theo ngày (HQTCSDL-36)
-- Chạy trong SSMS, tab AR_IMMS, CÙNG MỘT CỬA SỔ (có bảng tạm #r). Bôi đen từng phần rồi F5.
-- Thứ tự: 01..05 mới (đã đổi cột collected_at) -> PHẦN A (đo TRƯỚC) -> 17_telemetry_partition.sql
--         -> PHẦN A (đo SAU, chỉ chạy lại A2) -> PHẦN B (P1..P7) -> PHẦN C (dọn dẹp).
-- Dòng thử được đánh dấu bằng value = -999999 (dữ liệu hàng loạt) và -999998 (kiểm tra mốc ngày);
-- dữ liệu thật không bao giờ âm như vậy nên dọn dẹp an toàn.
-- ============================================================================
USE AR_IMMS;
GO

-- ############################ PHẦN A: dữ liệu thử + đo hiệu năng ###############
-- A1. Sinh 100.000 dòng trải đều 7 ngày gần nhất (chạy 1 lần; chạy lại không sinh thêm)
DECLARE @marker FLOAT = -999999;
IF NOT EXISTS (SELECT 1 FROM dbo.telemetry_metrics WHERE value = @marker)
BEGIN
    DECLARE @node INT = (SELECT MIN(id) FROM dbo.nodes);
    DECLARE @metric INT = (SELECT MIN(id) FROM dbo.metric_types);
    DECLARE @day0 DATETIME2(7) = CAST(DATEADD(DAY, -7, CAST(SYSUTCDATETIME() AS DATE)) AS DATETIME2(7));

    INSERT INTO dbo.telemetry_metrics (node_id, metric_type_id, value, collected_at)
    SELECT TOP (100000) @node, @metric, @marker,
           DATEADD(SECOND, ABS(CHECKSUM(NEWID())) % (7 * 86400), @day0)
    FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;
END

SELECT COUNT(*) AS dong_thu, MIN(collected_at) AS tu_utc, MAX(collected_at) AS den_utc
FROM dbo.telemetry_metrics WHERE value = -999999;
GO

-- A2. ĐO: truy vấn 1 ngày (3 ngày trước). Chạy TRƯỚC khi partition và SAU khi partition, ghi lại
--     logical reads (tab Messages) và CPU/elapsed time. Bật "Include Actual Execution Plan" (Ctrl+M).
--     Sau khi partition: chuột phải toán tử Clustered Index Seek -> Properties -> Actual Partition Count = 1.
DECLARE @d1 DATETIME2(7) = CAST(DATEADD(DAY, -3, CAST(SYSUTCDATETIME() AS DATE)) AS DATETIME2(7));
DECLARE @d2 DATETIME2(7) = DATEADD(DAY, 1, @d1);

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT COUNT(*) AS so_dong_ngay, AVG(value) AS gia_tri_tb
FROM dbo.telemetry_metrics
WHERE collected_at >= @d1 AND collected_at < @d2;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- ############################ PHẦN B: test case (chạy SAU 17) ###################
IF OBJECT_ID(N'tempdb..#r') IS NOT NULL DROP TABLE #r;
CREATE TABLE #r (ma NVARCHAR(10), noi_dung NVARCHAR(110), ket_qua NVARCHAR(6), chi_tiet NVARCHAR(250));
GO

-- P1: cấu trúc: clustered index (collected_at, node_id) nằm trên partition scheme, PK không cụm
BEGIN TRY
    DECLARE @keys NVARCHAR(200) = (
        SELECT STRING_AGG(c.name, N', ') WITHIN GROUP (ORDER BY ic.key_ordinal)
        FROM sys.indexes AS i
        JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
        JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = OBJECT_ID(N'dbo.telemetry_metrics') AND i.name = N'CIX_telemetry_collected_at_node');
    DECLARE @on_scheme INT = (
        SELECT COUNT(*) FROM sys.indexes AS i
        JOIN sys.partition_schemes AS ps ON ps.data_space_id = i.data_space_id
        WHERE i.object_id = OBJECT_ID(N'dbo.telemetry_metrics') AND i.name = N'CIX_telemetry_collected_at_node');
    DECLARE @pk_nc INT = (
        SELECT COUNT(*) FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.telemetry_metrics') AND is_primary_key = 1 AND type_desc = N'NONCLUSTERED');
    INSERT #r VALUES (N'P1', N'Clustered index (collected_at, node_id) trên partition scheme, PK không cụm',
        CASE WHEN @keys = N'collected_at, node_id' AND @on_scheme = 1 AND @pk_nc = 1 THEN N'PASS' ELSE N'FAIL' END,
        N'khóa=' + ISNULL(@keys, N'NULL') + N'; trên scheme=' + CAST(@on_scheme AS NVARCHAR(5)) + N'; PK nonclustered=' + CAST(@pk_nc AS NVARCHAR(5)));
END TRY
BEGIN CATCH
    INSERT #r VALUES (N'P1', N'Cấu trúc index', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- P2: tổng số dòng các partition = COUNT(*) của bảng (không mất dòng)
BEGIN TRY
    DECLARE @sum_part BIGINT = (SELECT SUM(p.rows) FROM sys.partitions AS p
                                WHERE p.object_id = OBJECT_ID(N'dbo.telemetry_metrics') AND p.index_id = 1);
    DECLARE @cnt BIGINT = (SELECT COUNT_BIG(*) FROM dbo.telemetry_metrics);
    INSERT #r VALUES (N'P2', N'Tổng số dòng các partition bằng số dòng của bảng',
        CASE WHEN @sum_part = @cnt THEN N'PASS' ELSE N'FAIL' END,
        N'tổng partition=' + CAST(@sum_part AS NVARCHAR(20)) + N'; COUNT(*)=' + CAST(@cnt AS NVARCHAR(20)));
END TRY
BEGIN CATCH
    INSERT #r VALUES (N'P2', N'Tổng số dòng các partition', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- P3: ranh giới ngày: 00:00:00 và 23:59:59.9999999 cùng ngày -> cùng partition; 00:00:00 ngày sau -> partition kế tiếp
BEGIN TRY
    DECLARE @node3 INT = (SELECT MIN(id) FROM dbo.nodes);
    DECLARE @metric3 INT = (SELECT MIN(id) FROM dbo.metric_types);
    DECLARE @D DATETIME2(7) = CAST(DATEADD(DAY, -20, CAST(SYSUTCDATETIME() AS DATE)) AS DATETIME2(7));

    DELETE FROM dbo.telemetry_metrics WHERE value = -999998;
    INSERT INTO dbo.telemetry_metrics (node_id, metric_type_id, value, collected_at) VALUES
        (@node3, @metric3, -999998, @D),
        (@node3, @metric3, -999998, DATEADD(HOUR, 12, @D)),
        (@node3, @metric3, -999998, DATEADD(NANOSECOND, -100, DATEADD(DAY, 1, @D))),
        (@node3, @metric3, -999998, DATEADD(DAY, 1, @D));

    DECLARE @p_start INT, @p_mid INT, @p_end INT, @p_next INT, @in_table INT;
    SELECT @p_start = $PARTITION.pf_telemetry_day(@D);
    SELECT @p_mid   = $PARTITION.pf_telemetry_day(DATEADD(HOUR, 12, @D));
    SELECT @p_end   = $PARTITION.pf_telemetry_day(DATEADD(NANOSECOND, -100, DATEADD(DAY, 1, @D)));
    SELECT @p_next  = $PARTITION.pf_telemetry_day(DATEADD(DAY, 1, @D));
    SELECT @in_table = COUNT(*) FROM dbo.telemetry_metrics
                       WHERE value = -999998 AND $PARTITION.pf_telemetry_day(collected_at) = @p_start;

    INSERT #r VALUES (N'P3', N'Ranh giới ngày: 00:00 / 12:00 / 23:59:59.99 cùng partition, 00:00 hôm sau sang partition kế',
        CASE WHEN @p_start = @p_mid AND @p_mid = @p_end AND @p_next = @p_start + 1 AND @in_table = 3 THEN N'PASS' ELSE N'FAIL' END,
        N'partition: đầu=' + CAST(@p_start AS NVARCHAR(5)) + N', giữa=' + CAST(@p_mid AS NVARCHAR(5))
        + N', cuối=' + CAST(@p_end AS NVARCHAR(5)) + N', hôm sau=' + CAST(@p_next AS NVARCHAR(5))
        + N'; dòng thật sự nằm trong partition ngày D=' + CAST(@in_table AS NVARCHAR(5)) + N' (cần 3)');
END TRY
BEGIN CATCH
    INSERT #r VALUES (N'P3', N'Ranh giới ngày', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- P4: toàn bộ dữ liệu của 1 ngày nằm trong đúng 1 partition (điều kiện cần để chỉ quét 1 partition)
--     Bằng chứng quét 1 partition: Actual Partition Count = 1 trong plan của PHẦN A (A2). 
BEGIN TRY
    DECLARE @d1 DATETIME2(7) = CAST(DATEADD(DAY, -3, CAST(SYSUTCDATETIME() AS DATE)) AS DATETIME2(7));
    DECLARE @d2 DATETIME2(7) = DATEADD(DAY, 1, @d1);
    DECLARE @parts INT = (SELECT COUNT(DISTINCT $PARTITION.pf_telemetry_day(collected_at))
                          FROM dbo.telemetry_metrics WHERE collected_at >= @d1 AND collected_at < @d2);
    DECLARE @rows_day BIGINT = (SELECT COUNT_BIG(*) FROM dbo.telemetry_metrics WHERE collected_at >= @d1 AND collected_at < @d2);
    INSERT #r VALUES (N'P4', N'Dữ liệu của 1 ngày nằm trong đúng 1 partition',
        CASE WHEN @parts = 1 AND @rows_day > 0 THEN N'PASS' ELSE N'FAIL' END,
        N'số partition chứa ngày đó=' + CAST(@parts AS NVARCHAR(5)) + N'; số dòng=' + CAST(@rows_day AS NVARCHAR(20))
        + N' (cần chạy PHẦN A1 để có dữ liệu)');
END TRY
BEGIN CATCH
    INSERT #r VALUES (N'P4', N'Dữ liệu 1 ngày trong 1 partition', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- P5: dòng ghi qua usp_record_telemetry rơi vào partition của ngày hôm nay
BEGIN TRY
    DECLARE @node5 INT = (SELECT MIN(id) FROM dbo.nodes);
    DECLARE @max_before BIGINT = (SELECT ISNULL(MAX(id), 0) FROM dbo.telemetry_metrics);
    EXEC dbo.usp_record_telemetry @node_id = @node5, @metric_type = N'cpu_usage_percent', @value = 20, @unit = N'%';
    DECLARE @new_part INT, @today_part INT;
    SELECT TOP (1) @new_part = $PARTITION.pf_telemetry_day(collected_at)
    FROM dbo.telemetry_metrics WHERE id > @max_before ORDER BY id;
    SELECT @today_part = $PARTITION.pf_telemetry_day(SYSUTCDATETIME());
    INSERT #r VALUES (N'P5', N'Dòng ghi qua usp_record_telemetry nằm ở partition của hôm nay',
        CASE WHEN @new_part IS NOT NULL AND @new_part = @today_part THEN N'PASS' ELSE N'FAIL' END,
        N'partition dòng mới=' + ISNULL(CAST(@new_part AS NVARCHAR(5)), N'NULL') + N'; partition hôm nay=' + CAST(@today_part AS NVARCHAR(5)));
    DELETE FROM dbo.telemetry_metrics WHERE id > @max_before AND node_id = @node5 AND value = 20;
END TRY
BEGIN CATCH
    INSERT #r VALUES (N'P5', N'usp_record_telemetry vào partition hôm nay', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- P6: usp_extend_telemetry_partitions: lần 1 có thể thêm mốc, lần 2 không thêm mốc trùng
BEGIN TRY
    DECLARE @b0 INT = (SELECT COUNT(*) FROM sys.partition_range_values AS prv
                       JOIN sys.partition_functions AS pf ON pf.function_id = prv.function_id WHERE pf.name = N'pf_telemetry_day');
    EXEC dbo.usp_extend_telemetry_partitions @days_ahead = 20;
    DECLARE @b1 INT = (SELECT COUNT(*) FROM sys.partition_range_values AS prv
                       JOIN sys.partition_functions AS pf ON pf.function_id = prv.function_id WHERE pf.name = N'pf_telemetry_day');
    EXEC dbo.usp_extend_telemetry_partitions @days_ahead = 20;
    DECLARE @b2 INT = (SELECT COUNT(*) FROM sys.partition_range_values AS prv
                       JOIN sys.partition_functions AS pf ON pf.function_id = prv.function_id WHERE pf.name = N'pf_telemetry_day');
    INSERT #r VALUES (N'P6', N'Thêm mốc partition: chạy lần 2 không thêm trùng',
        CASE WHEN @b1 >= @b0 AND @b2 = @b1 THEN N'PASS' ELSE N'FAIL' END,
        N'số mốc: trước=' + CAST(@b0 AS NVARCHAR(5)) + N', sau lần 1=' + CAST(@b1 AS NVARCHAR(5)) + N', sau lần 2=' + CAST(@b2 AS NVARCHAR(5)));
END TRY
BEGIN CATCH
    INSERT #r VALUES (N'P6', N'usp_extend_telemetry_partitions', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- P7: hồi quy: 2 view đọc telemetry_metrics vẫn chạy (sau đó nhớ chạy lại 06, 07 và POST /telemetry)
BEGIN TRY
    DECLARE @v1 INT = (SELECT COUNT(*) FROM dbo.vw_latest_telemetry);
    DECLARE @v2 INT = (SELECT COUNT(*) FROM dbo.vw_dashboard_summary);
    INSERT #r VALUES (N'P7', N'vw_latest_telemetry và vw_dashboard_summary vẫn chạy',
        N'PASS', N'vw_latest_telemetry=' + CAST(@v1 AS NVARCHAR(10)) + N' dòng; vw_dashboard_summary=' + CAST(@v2 AS NVARCHAR(10)) + N' dòng');
END TRY
BEGIN CATCH
    INSERT #r VALUES (N'P7', N'View đọc telemetry_metrics', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- Kết quả (CHỤP ẢNH)
SELECT ma, noi_dung, ket_qua, chi_tiet FROM #r ORDER BY ma;
GO

-- ############################ PHẦN C: dọn dẹp (sau khi chụp ảnh xong) ##########
-- Chỉ xóa các dòng thử (đánh dấu value âm); dữ liệu thật và các mốc partition được giữ nguyên.
DELETE FROM dbo.telemetry_metrics WHERE value IN (-999999, -999998);
DROP TABLE IF EXISTS #r;