-- ============================================================================
-- Đo trước/sau partition cho telemetry (HQTCSDL-37)
-- 3 truy vấn: Q1 thống kê 1 ngày; Q2 một node trong 24 giờ cuối; Q3 thống kê theo loại chỉ số trong 3 ngày.
-- Phương pháp: 2 bảng THỬ chứa CÙNG dữ liệu, chạy cùng truy vấn trong cùng phiên:
--   dbo.perf_telemetry_before : thiết kế CŨ (PK clustered trên id + 2 index không cụm node/metric theo thời gian)
--   dbo.perf_telemetry_after  : thiết kế MỚI của HQTCSDL-36 (partition theo ngày, clustered (collected_at, node_id))
-- Không đụng vào bảng telemetry_metrics thật. Dọn dẹp ở PHẦN 6 (DROP 2 bảng thử).
-- Yêu cầu: đã chạy 17_telemetry_partition.sql (cần pf_telemetry_day / ps_telemetry_day).
-- Chạy trong SSMS, tab AR_IMMS, CÙNG MỘT CỬA SỔ (dùng bảng tạm và SESSION_CONTEXT). Bôi đen từng phần rồi F5.
-- Chạy lại an toàn: PHẦN 1 chỉ sinh lại dữ liệu khi số dòng của 2 bảng chưa đủ @target_rows.
-- ============================================================================
USE AR_IMMS;
GO

-- ############################ PHẦN 1: tạo 2 bảng thử + sinh dữ liệu ###############
-- Dung lượng ổ đĩa (ước lượng, chưa đo): 2.000.000 dòng cần khoảng 1 GB gồm cả log (recovery FULL).
-- Xem ổ trống: EXEC master.sys.xp_fixeddrives;
DECLARE @target_rows INT = 2000000;   -- 1.000.000 (an toàn) / 2.000.000 (mặc định) / 5.000.000 (cần ổ trống > 10 GB, chạy lâu)
DECLARE @batch_rows  INT = 500000;
DECLARE @days        INT = 14;        -- dữ liệu trải 14 ngày UTC liên tiếp, kết thúc hôm qua

IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pf_telemetry_day')
   OR NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'ps_telemetry_day')
    THROW 51070, N'Run 20_telemetry_partition.sql first (pf_telemetry_day / ps_telemetry_day are required).', 1;

DECLARE @have_b BIGINT = 0, @have_a BIGINT = 0;
IF OBJECT_ID(N'dbo.perf_telemetry_before', N'U') IS NOT NULL SELECT @have_b = COUNT_BIG(*) FROM dbo.perf_telemetry_before;
IF OBJECT_ID(N'dbo.perf_telemetry_after',  N'U') IS NOT NULL SELECT @have_a = COUNT_BIG(*) FROM dbo.perf_telemetry_after;

IF @have_b = @target_rows AND @have_a = @target_rows
BEGIN
    PRINT N'SKIP: 2 bảng thử đã có đủ ' + CAST(@target_rows AS NVARCHAR(20)) + N' dòng.';
END
ELSE
BEGIN
    DROP TABLE IF EXISTS dbo.perf_telemetry_before;
    DROP TABLE IF EXISTS dbo.perf_telemetry_after;

    -- Thiết kế CŨ: PK clustered trên id (identity), index không cụm tạo sau khi nạp dữ liệu
    CREATE TABLE dbo.perf_telemetry_before (
        id             BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        node_id        INT           NOT NULL,
        metric_type_id INT           NOT NULL,
        value          FLOAT         NOT NULL,
        collected_at   DATETIME2(7)  NOT NULL
    );

    -- Thiết kế MỚI: nằm trên partition scheme theo ngày; clustered/PK/index tạo sau khi nạp dữ liệu
    CREATE TABLE dbo.perf_telemetry_after (
        id             BIGINT        NOT NULL,
        node_id        INT           NOT NULL,
        metric_type_id INT           NOT NULL,
        value          FLOAT         NOT NULL,
        collected_at   DATETIME2(7)  NOT NULL
    ) ON ps_telemetry_day (collected_at);

    -- Node và loại chỉ số thật của hệ thống, gán xoay vòng cho từng dòng
    CREATE TABLE #nodes   (rn INT NOT NULL PRIMARY KEY, id INT NOT NULL);
    CREATE TABLE #metrics (rn INT NOT NULL PRIMARY KEY, id INT NOT NULL);
    INSERT INTO #nodes   SELECT ROW_NUMBER() OVER (ORDER BY id), id FROM dbo.nodes;
    INSERT INTO #metrics SELECT ROW_NUMBER() OVER (ORDER BY id), id FROM dbo.metric_types;
    DECLARE @nn INT = (SELECT COUNT(*) FROM #nodes), @mm INT = (SELECT COUNT(*) FROM #metrics);
    IF @nn = 0 OR @mm = 0
        THROW 51071, N'nodes / metric_types are empty; run 03_seed_data.sql first.', 1;

    DECLARE @day0 DATETIME2(7) = CAST(DATEADD(DAY, -@days, CAST(SYSUTCDATETIME() AS DATE)) AS DATETIME2(7));
    DECLARE @first_boundary DATETIME2(7) = (
        SELECT MIN(CAST(prv.value AS DATETIME2(7)))
        FROM sys.partition_range_values AS prv
        JOIN sys.partition_functions AS pf ON pf.function_id = prv.function_id
        WHERE pf.name = N'pf_telemetry_day');
    IF @first_boundary > @day0
        PRINT N'WARNING: cửa sổ partition bắt đầu muộn hơn dữ liệu thử; một phần dữ liệu sẽ dồn vào partition 1.';

    -- Sinh dữ liệu theo từng lô; thời gian tăng đều theo id (giống dữ liệu ingest thật)
    DECLARE @done INT = 0, @take INT;
    WHILE @done < @target_rows
    BEGIN
        SET @take = CASE WHEN @target_rows - @done < @batch_rows THEN @target_rows - @done ELSE @batch_rows END;

        ;WITH g AS (
            SELECT TOP (@take) @done + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
            FROM sys.all_columns AS c CROSS JOIN sys.all_objects AS o
        )
        INSERT INTO dbo.perf_telemetry_before (node_id, metric_type_id, value, collected_at)
        SELECT nd.id, mt.id,
               CAST((CHECKSUM(NEWID()) & 2147483647) % 10000 AS FLOAT) / 100,
               DATEADD(MILLISECOND,
                       CAST(CAST(g.n - 1 AS FLOAT) * (@days * 86400000.0 / @target_rows) AS INT),
                       @day0)
        FROM g
        JOIN #nodes   AS nd ON nd.rn = (g.n % @nn) + 1
        JOIN #metrics AS mt ON mt.rn = ((g.n / @nn) % @mm) + 1;

        SET @done += @take;
        PRINT N'Đã sinh ' + CAST(@done AS NVARCHAR(20)) + N' / ' + CAST(@target_rows AS NVARCHAR(20)) + N' dòng';
    END

    -- Chép CÙNG dữ liệu sang bảng mới (giữ nguyên id)
    INSERT INTO dbo.perf_telemetry_after (id, node_id, metric_type_id, value, collected_at)
    SELECT id, node_id, metric_type_id, value, collected_at FROM dbo.perf_telemetry_before;

    -- Index sau khi nạp dữ liệu
    CREATE NONCLUSTERED INDEX IX_perf_before_node_time
        ON dbo.perf_telemetry_before (node_id, collected_at DESC);
    CREATE NONCLUSTERED INDEX IX_perf_before_metric_time
        ON dbo.perf_telemetry_before (metric_type_id, collected_at DESC);

    CREATE CLUSTERED INDEX CIX_perf_after_collected_at_node
        ON dbo.perf_telemetry_after (collected_at, node_id) ON ps_telemetry_day (collected_at);
    ALTER TABLE dbo.perf_telemetry_after
        ADD CONSTRAINT PK_perf_after PRIMARY KEY NONCLUSTERED (id, collected_at) ON ps_telemetry_day (collected_at);
    CREATE NONCLUSTERED INDEX IX_perf_after_node_time
        ON dbo.perf_telemetry_after (node_id, collected_at DESC) ON ps_telemetry_day (collected_at);
    CREATE NONCLUSTERED INDEX IX_perf_after_metric_time
        ON dbo.perf_telemetry_after (metric_type_id, collected_at DESC) ON ps_telemetry_day (collected_at);

    PRINT N'SUCCESS: đã tạo và nạp 2 bảng thử.';
END
GO

-- ############################ PHẦN 2: kiểm tra dữ liệu thử ##############
SELECT (SELECT COUNT_BIG(*) FROM dbo.perf_telemetry_before) AS dong_truoc,
       (SELECT COUNT_BIG(*) FROM dbo.perf_telemetry_after)  AS dong_sau;           -- bằng nhau

EXEC sys.sp_spaceused N'dbo.perf_telemetry_before';
EXEC sys.sp_spaceused N'dbo.perf_telemetry_after';

-- Bảng mới: dữ liệu rơi vào những partition nào (mỗi ngày một partition)
SELECT p.partition_number, CAST(prv.value AS DATETIME2(0)) AS tu_ngay_utc, p.rows AS so_dong
FROM sys.partitions AS p
LEFT JOIN sys.partition_functions AS pf ON pf.name = N'pf_telemetry_day'
LEFT JOIN sys.partition_range_values AS prv
       ON prv.function_id = pf.function_id AND prv.boundary_id = p.partition_number - 1
WHERE p.object_id = OBJECT_ID(N'dbo.perf_telemetry_after') AND p.index_id = 1 AND p.rows > 0
ORDER BY p.partition_number;
GO

-- ############################ PHẦN 3: đo tự động (bảng so sánh) ####################
-- 3.0 Chuẩn bị: mốc thời gian lấy theo dữ liệu thử (không phụ thuộc ngày chạy) và bảng #perf
IF OBJECT_ID(N'tempdb..#perf') IS NOT NULL DROP TABLE #perf;
CREATE TABLE #perf (label NVARCHAR(10), bang NVARCHAR(10), logical_reads BIGINT, cpu_ms INT, elapsed_ms INT);

DECLARE @end  DATETIME2(7) = DATEADD(DAY, 1, CAST((SELECT MAX(collected_at) FROM dbo.perf_telemetry_after) AS DATE));
DECLARE @node INT = (SELECT MIN(node_id) FROM dbo.perf_telemetry_after);
EXEC sys.sp_set_session_context @key = N'end_ts',  @value = @end;
EXEC sys.sp_set_session_context @key = N'node_id', @value = @node;
SELECT @end AS cuoi_ngay_du_lieu_utc, @node AS node_do;
GO

-- Mỗi batch lặp 3 lần 

-- Q1 TRƯỚC / SAU: thống kê 1 ngày
SET NOCOUNT ON;
DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
DECLARE @d1 DATETIME2(7) = DATEADD(DAY, -4, @end), @d2 DATETIME2(7) = DATEADD(DAY, -3, @end);
DECLARE @c BIGINT, @a FLOAT;
SELECT @c = COUNT_BIG(*), @a = AVG(value)
FROM dbo.perf_telemetry_before WHERE collected_at >= @d1 AND collected_at < @d2 OPTION (RECOMPILE);
INSERT #perf SELECT N'Q1', N'TRUOC', logical_reads, cpu_time, total_elapsed_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3

SET NOCOUNT ON;
DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
DECLARE @d1 DATETIME2(7) = DATEADD(DAY, -4, @end), @d2 DATETIME2(7) = DATEADD(DAY, -3, @end);
DECLARE @c BIGINT, @a FLOAT;
SELECT @c = COUNT_BIG(*), @a = AVG(value)
FROM dbo.perf_telemetry_after WHERE collected_at >= @d1 AND collected_at < @d2 OPTION (RECOMPILE);
INSERT #perf SELECT N'Q1', N'SAU', logical_reads, cpu_time, total_elapsed_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3

-- Q2 TRƯỚC / SAU: một node trong 24 giờ cuối
SET NOCOUNT ON;
DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
DECLARE @n INT = CAST(SESSION_CONTEXT(N'node_id') AS INT);
DECLARE @t1 DATETIME2(7) = DATEADD(DAY, -1, @end), @t2 DATETIME2(7) = @end;
DECLARE @c BIGINT, @mn DATETIME2(7), @mx DATETIME2(7), @a FLOAT;
SELECT @c = COUNT_BIG(*), @mn = MIN(collected_at), @mx = MAX(collected_at), @a = AVG(value)
FROM dbo.perf_telemetry_before WHERE node_id = @n AND collected_at >= @t1 AND collected_at < @t2 OPTION (RECOMPILE);
INSERT #perf SELECT N'Q2', N'TRUOC', logical_reads, cpu_time, total_elapsed_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3

SET NOCOUNT ON;
DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
DECLARE @n INT = CAST(SESSION_CONTEXT(N'node_id') AS INT);
DECLARE @t1 DATETIME2(7) = DATEADD(DAY, -1, @end), @t2 DATETIME2(7) = @end;
DECLARE @c BIGINT, @mn DATETIME2(7), @mx DATETIME2(7), @a FLOAT;
SELECT @c = COUNT_BIG(*), @mn = MIN(collected_at), @mx = MAX(collected_at), @a = AVG(value)
FROM dbo.perf_telemetry_after WHERE node_id = @n AND collected_at >= @t1 AND collected_at < @t2 OPTION (RECOMPILE);
INSERT #perf SELECT N'Q2', N'SAU', logical_reads, cpu_time, total_elapsed_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3

-- Q3 TRƯỚC / SAU: thống kê theo loại chỉ số trong 3 ngày cuối
SET NOCOUNT ON;
DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
DECLARE @e1 DATETIME2(7) = DATEADD(DAY, -3, @end), @e2 DATETIME2(7) = @end;
DECLARE @k INT;
SELECT @k = COUNT(*) FROM (
    SELECT metric_type_id, COUNT_BIG(*) AS so_dong, AVG(value) AS tb, MAX(value) AS lon_nhat
    FROM dbo.perf_telemetry_before WHERE collected_at >= @e1 AND collected_at < @e2
    GROUP BY metric_type_id) AS x OPTION (RECOMPILE);
INSERT #perf SELECT N'Q3', N'TRUOC', logical_reads, cpu_time, total_elapsed_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3

SET NOCOUNT ON;
DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
DECLARE @e1 DATETIME2(7) = DATEADD(DAY, -3, @end), @e2 DATETIME2(7) = @end;
DECLARE @k INT;
SELECT @k = COUNT(*) FROM (
    SELECT metric_type_id, COUNT_BIG(*) AS so_dong, AVG(value) AS tb, MAX(value) AS lon_nhat
    FROM dbo.perf_telemetry_after WHERE collected_at >= @e1 AND collected_at < @e2
    GROUP BY metric_type_id) AS x OPTION (RECOMPILE);
INSERT #perf SELECT N'Q3', N'SAU', logical_reads, cpu_time, total_elapsed_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3

-- 3.7 BẢNG SO SÁNH: lấy lần chạy nhanh nhất của mỗi truy vấn
SELECT q.label AS truy_van,
       b.reads AS reads_truoc, a.reads AS reads_sau,
       CAST(1.0 * b.reads / NULLIF(a.reads, 0) AS DECIMAL(12,1)) AS reads_giam_x_lan,
       b.cpu AS cpu_ms_truoc, a.cpu AS cpu_ms_sau,
       b.elapsed AS elapsed_ms_truoc, a.elapsed AS elapsed_ms_sau
FROM (SELECT DISTINCT label FROM #perf) AS q
CROSS APPLY (SELECT MIN(logical_reads) AS reads, MIN(cpu_ms) AS cpu, MIN(elapsed_ms) AS elapsed
             FROM #perf WHERE label = q.label AND bang = N'TRUOC') AS b
CROSS APPLY (SELECT MIN(logical_reads) AS reads, MIN(cpu_ms) AS cpu, MIN(elapsed_ms) AS elapsed
             FROM #perf WHERE label = q.label AND bang = N'SAU') AS a
ORDER BY q.label;
GO

-- ############################ PHẦN 4: STATISTICS IO/TIME + execution plan (CHỤP ẢNH) ##
-- Bật "Include Actual Execution Plan" (Ctrl+M), bôi đen từng khối rồi F5. Mỗi khối chạy cả bảng TRƯỚC và SAU:
-- tab Execution plan hiện 2 plan cạnh nhau; tab Messages hiện logical reads / CPU / elapsed time.
-- Ở plan bảng SAU: chuột phải toán tử Clustered Index Seek/Scan -> Properties -> "Actual Partition Count".
-- (Có thể lưu plan: chuột phải vào plan -> Save Execution Plan As... .sqlplan để đính kèm Jira.)

-- Q1
SET STATISTICS IO ON; SET STATISTICS TIME ON;
DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
DECLARE @d1 DATETIME2(7) = DATEADD(DAY, -4, @end), @d2 DATETIME2(7) = DATEADD(DAY, -3, @end);
SELECT COUNT_BIG(*) AS so_dong, AVG(value) AS gia_tri_tb
FROM dbo.perf_telemetry_before WHERE collected_at >= @d1 AND collected_at < @d2 OPTION (RECOMPILE);   -- TRƯỚC
SELECT COUNT_BIG(*) AS so_dong, AVG(value) AS gia_tri_tb
FROM dbo.perf_telemetry_after  WHERE collected_at >= @d1 AND collected_at < @d2 OPTION (RECOMPILE);   -- SAU
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
GO

-- Q2
SET STATISTICS IO ON; SET STATISTICS TIME ON;
DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
DECLARE @n INT = CAST(SESSION_CONTEXT(N'node_id') AS INT);
DECLARE @t1 DATETIME2(7) = DATEADD(DAY, -1, @end), @t2 DATETIME2(7) = @end;
SELECT COUNT_BIG(*) AS so_diem, MIN(collected_at) AS som_nhat, MAX(collected_at) AS muon_nhat, AVG(value) AS gia_tri_tb
FROM dbo.perf_telemetry_before WHERE node_id = @n AND collected_at >= @t1 AND collected_at < @t2 OPTION (RECOMPILE);   -- TRƯỚC
SELECT COUNT_BIG(*) AS so_diem, MIN(collected_at) AS som_nhat, MAX(collected_at) AS muon_nhat, AVG(value) AS gia_tri_tb
FROM dbo.perf_telemetry_after  WHERE node_id = @n AND collected_at >= @t1 AND collected_at < @t2 OPTION (RECOMPILE);   -- SAU
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
GO

-- Q3
SET STATISTICS IO ON; SET STATISTICS TIME ON;
DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
DECLARE @e1 DATETIME2(7) = DATEADD(DAY, -3, @end), @e2 DATETIME2(7) = @end;
SELECT metric_type_id, COUNT_BIG(*) AS so_dong, AVG(value) AS tb, MAX(value) AS lon_nhat
FROM dbo.perf_telemetry_before WHERE collected_at >= @e1 AND collected_at < @e2
GROUP BY metric_type_id ORDER BY metric_type_id OPTION (RECOMPILE);                                                 -- TRƯỚC
SELECT metric_type_id, COUNT_BIG(*) AS so_dong, AVG(value) AS tb, MAX(value) AS lon_nhat
FROM dbo.perf_telemetry_after  WHERE collected_at >= @e1 AND collected_at < @e2
GROUP BY metric_type_id ORDER BY metric_type_id OPTION (RECOMPILE);                                                 -- SAU
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
GO

-- ############################ PHẦN 5: test case - kết quả 2 bảng phải GIỐNG NHAU ###
IF OBJECT_ID(N'tempdb..#r37') IS NOT NULL DROP TABLE #r37;
CREATE TABLE #r37 (ma NVARCHAR(10), noi_dung NVARCHAR(110), ket_qua NVARCHAR(6), chi_tiet NVARCHAR(250));
GO

-- R1: cùng số dòng
BEGIN TRY
    DECLARE @r1b BIGINT = (SELECT COUNT_BIG(*) FROM dbo.perf_telemetry_before);
    DECLARE @r1a BIGINT = (SELECT COUNT_BIG(*) FROM dbo.perf_telemetry_after);
    INSERT #r37 VALUES (N'R1', N'Hai bảng có cùng số dòng', CASE WHEN @r1b = @r1a AND @r1b > 0 THEN N'PASS' ELSE N'FAIL' END,
        N'trước=' + CAST(@r1b AS NVARCHAR(20)) + N'; sau=' + CAST(@r1a AS NVARCHAR(20)));
END TRY
BEGIN CATCH
    INSERT #r37 VALUES (N'R1', N'Số dòng', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- R2: số dòng theo từng ngày giống nhau
BEGIN TRY
    DECLARE @r2 INT = (SELECT COUNT(*) FROM (
        (SELECT CAST(collected_at AS DATE) AS d, COUNT_BIG(*) AS c FROM dbo.perf_telemetry_before GROUP BY CAST(collected_at AS DATE)
         EXCEPT
         SELECT CAST(collected_at AS DATE), COUNT_BIG(*) FROM dbo.perf_telemetry_after GROUP BY CAST(collected_at AS DATE))
        UNION ALL
        (SELECT CAST(collected_at AS DATE), COUNT_BIG(*) FROM dbo.perf_telemetry_after GROUP BY CAST(collected_at AS DATE)
         EXCEPT
         SELECT CAST(collected_at AS DATE), COUNT_BIG(*) FROM dbo.perf_telemetry_before GROUP BY CAST(collected_at AS DATE))) AS x);
    INSERT #r37 VALUES (N'R2', N'Số dòng theo từng ngày giống nhau', CASE WHEN @r2 = 0 THEN N'PASS' ELSE N'FAIL' END,
        N'số ngày lệch=' + CAST(@r2 AS NVARCHAR(10)) + N' (cần 0)');
END TRY
BEGIN CATCH
    INSERT #r37 VALUES (N'R2', N'Số dòng theo ngày', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- R3: Q1 cho cùng kết quả
BEGIN TRY
    DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
    DECLARE @d1 DATETIME2(7) = DATEADD(DAY, -4, @end), @d2 DATETIME2(7) = DATEADD(DAY, -3, @end);
    DECLARE @c1 BIGINT, @a1 FLOAT, @c2 BIGINT, @a2 FLOAT;
    SELECT @c1 = COUNT_BIG(*), @a1 = AVG(value) FROM dbo.perf_telemetry_before WHERE collected_at >= @d1 AND collected_at < @d2;
    SELECT @c2 = COUNT_BIG(*), @a2 = AVG(value) FROM dbo.perf_telemetry_after  WHERE collected_at >= @d1 AND collected_at < @d2;
    INSERT #r37 VALUES (N'R3', N'Q1 (thống kê 1 ngày): kết quả giống nhau',
        CASE WHEN @c1 = @c2 AND @c1 > 0 AND ABS(@a1 - @a2) < 0.000001 THEN N'PASS' ELSE N'FAIL' END,
        N'số dòng: ' + CAST(@c1 AS NVARCHAR(20)) + N' / ' + CAST(@c2 AS NVARCHAR(20))
        + N'; trung bình: ' + CAST(@a1 AS NVARCHAR(30)) + N' / ' + CAST(@a2 AS NVARCHAR(30)));
END TRY
BEGIN CATCH
    INSERT #r37 VALUES (N'R3', N'Q1', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- R4: Q2 cho cùng kết quả
BEGIN TRY
    DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
    DECLARE @n INT = CAST(SESSION_CONTEXT(N'node_id') AS INT);
    DECLARE @t1 DATETIME2(7) = DATEADD(DAY, -1, @end), @t2 DATETIME2(7) = @end;
    DECLARE @c1 BIGINT, @a1 FLOAT, @mn1 DATETIME2(7), @mx1 DATETIME2(7);
    DECLARE @c2 BIGINT, @a2 FLOAT, @mn2 DATETIME2(7), @mx2 DATETIME2(7);
    SELECT @c1 = COUNT_BIG(*), @a1 = AVG(value), @mn1 = MIN(collected_at), @mx1 = MAX(collected_at)
    FROM dbo.perf_telemetry_before WHERE node_id = @n AND collected_at >= @t1 AND collected_at < @t2;
    SELECT @c2 = COUNT_BIG(*), @a2 = AVG(value), @mn2 = MIN(collected_at), @mx2 = MAX(collected_at)
    FROM dbo.perf_telemetry_after WHERE node_id = @n AND collected_at >= @t1 AND collected_at < @t2;
    INSERT #r37 VALUES (N'R4', N'Q2 (1 node, 24 giờ): kết quả giống nhau',
        CASE WHEN @c1 = @c2 AND @c1 > 0 AND @mn1 = @mn2 AND @mx1 = @mx2 AND ABS(@a1 - @a2) < 0.000001 THEN N'PASS' ELSE N'FAIL' END,
        N'số điểm: ' + CAST(@c1 AS NVARCHAR(20)) + N' / ' + CAST(@c2 AS NVARCHAR(20)));
END TRY
BEGIN CATCH
    INSERT #r37 VALUES (N'R4', N'Q2', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- R5: Q3 cho cùng kết quả theo từng loại chỉ số
BEGIN TRY
    DROP TABLE IF EXISTS #q3b, #q3a;
    DECLARE @end DATETIME2(7) = CAST(SESSION_CONTEXT(N'end_ts') AS DATETIME2(7));
    DECLARE @e1 DATETIME2(7) = DATEADD(DAY, -3, @end), @e2 DATETIME2(7) = @end;
    SELECT metric_type_id, COUNT_BIG(*) AS so_dong, AVG(value) AS tb, MAX(value) AS lon_nhat
    INTO #q3b FROM dbo.perf_telemetry_before WHERE collected_at >= @e1 AND collected_at < @e2 GROUP BY metric_type_id;
    SELECT metric_type_id, COUNT_BIG(*) AS so_dong, AVG(value) AS tb, MAX(value) AS lon_nhat
    INTO #q3a FROM dbo.perf_telemetry_after WHERE collected_at >= @e1 AND collected_at < @e2 GROUP BY metric_type_id;
    DECLARE @bad INT = (SELECT COUNT(*) FROM #q3b AS b FULL JOIN #q3a AS a ON a.metric_type_id = b.metric_type_id
                        WHERE a.metric_type_id IS NULL OR b.metric_type_id IS NULL
                           OR a.so_dong <> b.so_dong OR a.lon_nhat <> b.lon_nhat OR ABS(a.tb - b.tb) > 0.000001);
    DECLARE @groups INT = (SELECT COUNT(*) FROM #q3b);
    INSERT #r37 VALUES (N'R5', N'Q3 (theo loại chỉ số, 3 ngày): kết quả giống nhau',
        CASE WHEN @bad = 0 AND @groups > 0 THEN N'PASS' ELSE N'FAIL' END,
        N'số nhóm=' + CAST(@groups AS NVARCHAR(10)) + N'; nhóm lệch=' + CAST(@bad AS NVARCHAR(10)) + N' (cần 0)');
    DROP TABLE #q3b; DROP TABLE #q3a;
END TRY
BEGIN CATCH
    INSERT #r37 VALUES (N'R5', N'Q3', N'FAIL', LEFT(ERROR_MESSAGE(), 250));
END CATCH
GO

-- Kết quả test (CHỤP ẢNH)
SELECT ma, noi_dung, ket_qua, chi_tiet FROM #r37 ORDER BY ma;
GO

-- ############################ PHẦN 6: dọn dẹp (sau khi chụp ảnh xong) ###############
-- Chỉ xóa 2 bảng thử của phần này; telemetry_metrics thật không bị đụng.
-- DROP TABLE IF EXISTS dbo.perf_telemetry_before;
-- TABLE IF EXISTS dbo.perf_telemetry_after;
-- DROP TABLE IF EXISTS #perf;
-- DROP TABLE IF EXISTS #r37;