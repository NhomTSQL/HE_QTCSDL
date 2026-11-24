-- ============================================================================
-- AR-IMMS: Scale Architecture (Snapshot, Partitioning, Columnstore,
--          Batch Ingest via OPENJSON, Operational Indexes & Pagination)
-- Rerunnable (idempotent); apply after scripts 01-20.
-- ============================================================================

USE AR_IMMS;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 1. BẢNG SNAPSHOT O(1) CHO DASHBOARD: dbo.node_latest_metrics
--    Thay vì quét toàn bộ lịch sử telemetry_metrics bằng ROW_NUMBER()
-- ═══════════════════════════════════════════════════════════════════
IF OBJECT_ID(N'dbo.node_latest_metrics', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.node_latest_metrics (
        node_id         INT         NOT NULL,
        metric_type_id  INT         NOT NULL,
        value           FLOAT       NOT NULL,
        timestamp       DATETIME2   NOT NULL,

        CONSTRAINT PK_node_latest_metrics PRIMARY KEY CLUSTERED (node_id, metric_type_id),
        CONSTRAINT FK_latest_metrics_node FOREIGN KEY (node_id)
            REFERENCES dbo.nodes(id) ON DELETE CASCADE,
        CONSTRAINT FK_latest_metrics_type FOREIGN KEY (metric_type_id)
            REFERENCES dbo.metric_types(id)
    );
END;
GO

-- Backfill snapshot từ dữ liệu telemetry hiện có (an toàn khi chạy lại)
;WITH ranked AS (
    SELECT node_id,
           metric_type_id,
           value,
           timestamp,
           ROW_NUMBER() OVER (
               PARTITION BY node_id, metric_type_id
               ORDER BY timestamp DESC, id DESC
           ) AS rn
    FROM dbo.telemetry_metrics
)
MERGE dbo.node_latest_metrics AS tgt
USING (
    SELECT node_id, metric_type_id, value, timestamp
    FROM ranked
    WHERE rn = 1
) AS src
ON tgt.node_id = src.node_id AND tgt.metric_type_id = src.metric_type_id
WHEN MATCHED AND src.timestamp >= tgt.timestamp THEN
    UPDATE SET tgt.value = src.value, tgt.timestamp = src.timestamp
WHEN NOT MATCHED THEN
    INSERT (node_id, metric_type_id, value, timestamp)
    VALUES (src.node_id, src.metric_type_id, src.value, src.timestamp);
GO

CREATE OR ALTER VIEW dbo.vw_latest_telemetry
AS
SELECT lm.node_id,
       mt.code AS metric_type,
       lm.value,
       mt.unit,
       lm.timestamp
FROM dbo.node_latest_metrics lm
INNER JOIN dbo.metric_types mt ON mt.id = lm.metric_type_id;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 2. TABLE PARTITIONING THEO THÁNG TRÊN dbo.telemetry_metrics
--    Hỗ trợ Partition Pruning và xóa nhanh bằng SWITCH PARTITION
-- ═══════════════════════════════════════════════════════════════════
IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'PF_TelemetryMonth')
BEGIN
    CREATE PARTITION FUNCTION PF_TelemetryMonth (DATETIME2)
    AS RANGE RIGHT FOR VALUES (
        '2026-06-01', '2026-07-01', '2026-08-01', '2026-09-01',
        '2026-10-01', '2026-11-01', '2026-12-01', '2027-01-01',
        '2027-02-01', '2027-03-01', '2027-04-01', '2027-05-01',
        '2027-06-01', '2027-07-01', '2027-08-01', '2027-09-01',
        '2027-10-01', '2027-11-01', '2027-12-01'
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'PS_TelemetryMonth')
BEGIN
    CREATE PARTITION SCHEME PS_TelemetryMonth
    AS PARTITION PF_TelemetryMonth
    ALL TO ([PRIMARY]);
END;
GO

-- Chuyển Clustered PK sang PS_TelemetryMonth(timestamp) nếu chưa được partition
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    INNER JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
    WHERE i.object_id = OBJECT_ID(N'dbo.telemetry_metrics')
      AND i.index_id = 1
      AND ds.name = N'PS_TelemetryMonth'
)
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'NCCI_telemetry_analytics' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
        DROP INDEX NCCI_telemetry_analytics ON dbo.telemetry_metrics;

    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_node_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
        DROP INDEX IX_telemetry_node_time ON dbo.telemetry_metrics;

    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_metric_type_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
        DROP INDEX IX_telemetry_metric_type_time ON dbo.telemetry_metrics;

    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_node_metric_time_inc' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
        DROP INDEX IX_telemetry_node_metric_time_inc ON dbo.telemetry_metrics;

    DECLARE @pk_name SYSNAME = (
        SELECT TOP (1) kc.name
        FROM sys.key_constraints kc
        WHERE kc.parent_object_id = OBJECT_ID(N'dbo.telemetry_metrics')
          AND kc.type = N'PK'
    );
    IF @pk_name IS NOT NULL
    BEGIN
        DECLARE @drop_pk NVARCHAR(MAX) = N'ALTER TABLE dbo.telemetry_metrics DROP CONSTRAINT ' + QUOTENAME(@pk_name) + N';';
        EXEC sys.sp_executesql @drop_pk;
    END;

    ALTER TABLE dbo.telemetry_metrics
        ADD CONSTRAINT PK_telemetry_metrics PRIMARY KEY CLUSTERED (id, timestamp)
        ON PS_TelemetryMonth(timestamp);
END;
GO

-- Bảo đảm các index trên dbo.telemetry_metrics đều partition-aligned trên PS_TelemetryMonth
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes i
    INNER JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
    WHERE i.name = N'IX_telemetry_node_time'
      AND i.object_id = OBJECT_ID(N'dbo.telemetry_metrics')
      AND ds.name = N'PS_TelemetryMonth'
)
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_node_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
        DROP INDEX IX_telemetry_node_time ON dbo.telemetry_metrics;

    CREATE NONCLUSTERED INDEX IX_telemetry_node_time
        ON dbo.telemetry_metrics (node_id, timestamp DESC)
        ON PS_TelemetryMonth(timestamp);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes i
    INNER JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
    WHERE i.name = N'IX_telemetry_metric_type_time'
      AND i.object_id = OBJECT_ID(N'dbo.telemetry_metrics')
      AND ds.name = N'PS_TelemetryMonth'
)
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_metric_type_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
        DROP INDEX IX_telemetry_metric_type_time ON dbo.telemetry_metrics;

    CREATE NONCLUSTERED INDEX IX_telemetry_metric_type_time
        ON dbo.telemetry_metrics (metric_type_id, timestamp DESC)
        ON PS_TelemetryMonth(timestamp);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes i
    INNER JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
    WHERE i.name = N'IX_telemetry_node_metric_time_inc'
      AND i.object_id = OBJECT_ID(N'dbo.telemetry_metrics')
      AND ds.name = N'PS_TelemetryMonth'
)
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_node_metric_time_inc' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
        DROP INDEX IX_telemetry_node_metric_time_inc ON dbo.telemetry_metrics;

    CREATE NONCLUSTERED INDEX IX_telemetry_node_metric_time_inc
        ON dbo.telemetry_metrics (node_id, metric_type_id, timestamp DESC)
        INCLUDE (value)
        ON PS_TelemetryMonth(timestamp);
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 3. NONCLUSTERED COLUMNSTORE INDEX CHO BÁO CÁO PHÂN TÍCH (COULD)
-- ═══════════════════════════════════════════════════════════════════
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'NCCI_telemetry_analytics'
      AND object_id = OBJECT_ID(N'dbo.telemetry_metrics')
)
BEGIN
    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_telemetry_analytics
        ON dbo.telemetry_metrics (node_id, metric_type_id, timestamp, value)
        ON PS_TelemetryMonth(timestamp);
END;
GO

-- Bảng staging đồng bộ schema + indexes để hỗ trợ SWITCH PARTITION O(1)
IF OBJECT_ID(N'dbo.telemetry_metrics_archive_staging', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.telemetry_metrics_archive_staging (
        id              BIGINT IDENTITY(1,1) NOT NULL,
        node_id         INT                  NOT NULL,
        metric_type_id  INT                  NOT NULL,
        value           FLOAT                NOT NULL,
        timestamp       DATETIME2            NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_telemetry_metrics_staging PRIMARY KEY CLUSTERED (id, timestamp)
            ON PS_TelemetryMonth(timestamp),
        CONSTRAINT FK_telemetry_staging_node FOREIGN KEY (node_id)
            REFERENCES dbo.nodes(id),
        CONSTRAINT FK_telemetry_staging_metric_type FOREIGN KEY (metric_type_id)
            REFERENCES dbo.metric_types(id)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_staging_node_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics_archive_staging'))
    CREATE NONCLUSTERED INDEX IX_telemetry_staging_node_time ON dbo.telemetry_metrics_archive_staging (node_id, timestamp DESC) ON PS_TelemetryMonth(timestamp);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_staging_metric_type_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics_archive_staging'))
    CREATE NONCLUSTERED INDEX IX_telemetry_staging_metric_type_time ON dbo.telemetry_metrics_archive_staging (metric_type_id, timestamp DESC) ON PS_TelemetryMonth(timestamp);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_staging_node_metric_time_inc' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics_archive_staging'))
    CREATE NONCLUSTERED INDEX IX_telemetry_staging_node_metric_time_inc ON dbo.telemetry_metrics_archive_staging (node_id, metric_type_id, timestamp DESC) INCLUDE (value) ON PS_TelemetryMonth(timestamp);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'NCCI_telemetry_staging_analytics' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics_archive_staging'))
    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_telemetry_staging_analytics ON dbo.telemetry_metrics_archive_staging (node_id, metric_type_id, timestamp, value) ON PS_TelemetryMonth(timestamp);
GO

CREATE OR ALTER PROCEDURE dbo.usp_purge_telemetry_partition
    @partition_number INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @partition_number IS NULL OR @partition_number < 1
        THROW 51092, N'Invalid partition_number.', 1;

    DECLARE @max_part INT = (
        SELECT MAX(partition_number)
        FROM sys.partitions
        WHERE object_id = OBJECT_ID(N'dbo.telemetry_metrics') AND index_id = 1
    );
    IF @partition_number >= @max_part
        THROW 51092, N'Cannot purge active future-most partition.', 1;

    TRUNCATE TABLE dbo.telemetry_metrics_archive_staging;

    DECLARE @switch_sql NVARCHAR(MAX) =
        N'ALTER TABLE dbo.telemetry_metrics SWITCH PARTITION '
        + CAST(@partition_number AS NVARCHAR(10))
        + N' TO dbo.telemetry_metrics_archive_staging PARTITION '
        + CAST(@partition_number AS NVARCHAR(10)) + N';';
    EXEC sys.sp_executesql @switch_sql;

    DECLARE @switched_rows BIGINT = (SELECT COUNT_BIG(*) FROM dbo.telemetry_metrics_archive_staging);
    TRUNCATE TABLE dbo.telemetry_metrics_archive_staging;

    INSERT INTO dbo.audit_logs (username, action, target_entity, target_id, details_json, timestamp)
    VALUES (N'SYSTEM', N'TELEMETRY_PARTITION_PURGED', N'telemetry_metrics',
            CAST(@partition_number AS NVARCHAR(20)),
            N'{"partition_number":' + CAST(@partition_number AS NVARCHAR(10))
                + N',"purged_rows":' + CAST(@switched_rows AS NVARCHAR(20)) + N'}',
            SYSUTCDATETIME());

    SELECT @partition_number AS partition_number, @switched_rows AS purged_rows;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 4. OPERATIONAL INDEXES BỔ SUNG (AGENT AUTH, ALERTS, TICKETS, NOTIF)
-- ═══════════════════════════════════════════════════════════════════
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_agents_api_key_hash' AND object_id = OBJECT_ID(N'dbo.data_collector_agents'))
    CREATE NONCLUSTERED INDEX IX_agents_api_key_hash ON dbo.data_collector_agents (api_key_hash, status) INCLUDE (node_id);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_alerts_status_triggered' AND object_id = OBJECT_ID(N'dbo.alerts'))
    CREATE NONCLUSTERED INDEX IX_alerts_status_triggered ON dbo.alerts (status, triggered_at DESC) INCLUDE (node_id, alert_type, severity);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_tickets_status_created' AND object_id = OBJECT_ID(N'dbo.tickets'))
    CREATE NONCLUSTERED INDEX IX_tickets_status_created ON dbo.tickets (status, created_at DESC) INCLUDE (node_id, priority, assigned_to_user_id);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_tickets_node_id' AND object_id = OBJECT_ID(N'dbo.tickets'))
    CREATE NONCLUSTERED INDEX IX_tickets_node_id ON dbo.tickets (node_id, created_at DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_notifications_user_read' AND object_id = OBJECT_ID(N'dbo.notifications'))
    CREATE NONCLUSTERED INDEX IX_notifications_user_read ON dbo.notifications (user_id, is_read, created_at DESC);
GO

-- ═══════════════════════════════════════════════════════════════════
-- 5. CẬP NHẬT usp_record_telemetry & TẠO usp_record_telemetry_batch
-- ═══════════════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE dbo.usp_record_telemetry
    @node_id        INT,
    @metric_type    NVARCHAR(50),
    @value          FLOAT,
    @unit           NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @metric_type_id INT, @canonical_unit NVARCHAR(20);
    SELECT @metric_type_id = id, @canonical_unit = unit
    FROM dbo.metric_types
    WHERE code = @metric_type;

    IF @metric_type_id IS NULL
        THROW 51030, N'Unknown telemetry metric type.', 1;

    IF @canonical_unit IS NULL OR @canonical_unit <> @unit
        THROW 51031, N'Telemetry unit does not match the metric type.', 1;

    DECLARE @threshold_id INT, @warning FLOAT, @critical FLOAT;
    SELECT @threshold_id = id,
           @warning = warning_threshold,
           @critical = critical_threshold
    FROM dbo.alert_thresholds
    WHERE metric_type_id = @metric_type_id AND is_active = 1;

    DECLARE @now DATETIME2 = SYSUTCDATETIME();
    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

    BEGIN TRY
        IF @own_tran = 1
            BEGIN TRANSACTION;

        INSERT INTO dbo.telemetry_metrics (node_id, metric_type_id, value, timestamp)
        VALUES (@node_id, @metric_type_id, @value, @now);

        MERGE dbo.node_latest_metrics AS tgt
        USING (SELECT @node_id AS node_id, @metric_type_id AS metric_type_id) AS src
        ON tgt.node_id = src.node_id AND tgt.metric_type_id = src.metric_type_id
        WHEN MATCHED THEN
            UPDATE SET tgt.value = @value, tgt.timestamp = @now
        WHEN NOT MATCHED THEN
            INSERT (node_id, metric_type_id, value, timestamp)
            VALUES (@node_id, @metric_type_id, @value, @now);

        UPDATE dbo.alerts
        SET status = N'RESOLVED',
            resolved_at = @now
        WHERE node_id = @node_id
          AND alert_type = N'NODE_UNAVAILABLE'
          AND status IN (N'OPEN', N'ACKNOWLEDGED');

        UPDATE dbo.nodes
        SET last_ping_at = @now,
            status = CASE
                WHEN status = N'MAINTENANCE' THEN N'MAINTENANCE'
                WHEN @threshold_id IS NOT NULL
                     AND @metric_type IN (N'cpu_usage_percent', N'temperature_celsius')
                     AND @value >= @critical THEN N'CRITICAL'
                WHEN @threshold_id IS NOT NULL
                     AND @metric_type IN (N'cpu_usage_percent', N'temperature_celsius')
                     AND @value >= @warning THEN N'WARNING'
                WHEN @threshold_id IS NOT NULL
                     AND @metric_type IN (N'cpu_usage_percent', N'temperature_celsius')
                     AND @value < @warning
                     AND NOT EXISTS (
                         SELECT 1
                         FROM dbo.alerts a
                         WHERE a.node_id = @node_id
                           AND a.severity = N'CRITICAL'
                           AND a.status IN (N'OPEN', N'ACKNOWLEDGED')
                     ) THEN N'ONLINE'
                WHEN status = N'UNAVAILABLE'
                     AND NOT EXISTS (
                         SELECT 1
                         FROM dbo.alerts a
                         WHERE a.node_id = @node_id
                           AND a.severity = N'CRITICAL'
                           AND a.status IN (N'OPEN', N'ACKNOWLEDGED')
                     ) THEN N'ONLINE'
                WHEN status = N'UNAVAILABLE' THEN N'CRITICAL'
                ELSE status
            END
        WHERE id = @node_id;

        IF @threshold_id IS NOT NULL AND @value >= @warning
        BEGIN
            DECLARE @alert_type NVARCHAR(50) = @metric_type + N'_OVERLOAD';

            IF @value >= @critical
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM dbo.alerts
                    WHERE node_id = @node_id
                      AND alert_type = @alert_type
                      AND severity = N'WARNING'
                      AND status IN (N'OPEN', N'ACKNOWLEDGED')
                )
                BEGIN
                    UPDATE dbo.alerts
                    SET severity = N'CRITICAL',
                        metric_value = @value,
                        message = N'Cảnh báo CRITICAL: ' + @metric_type + N' = '
                                  + CAST(@value AS NVARCHAR(20)) + N' vượt ngưỡng '
                                  + CAST(@critical AS NVARCHAR(20)),
                        triggered_at = @now
                    WHERE node_id = @node_id
                      AND alert_type = @alert_type
                      AND severity = N'WARNING'
                      AND status IN (N'OPEN', N'ACKNOWLEDGED');
                END
                ELSE
                BEGIN
                    BEGIN TRY
                        INSERT INTO dbo.alerts (node_id, threshold_id, alert_type, severity, status,
                                                message, metric_value, triggered_at)
                        SELECT @node_id, @threshold_id, @alert_type, N'CRITICAL', N'OPEN',
                               N'Cảnh báo CRITICAL: ' + @metric_type + N' = '
                                   + CAST(@value AS NVARCHAR(20)) + N' vượt ngưỡng '
                                   + CAST(@critical AS NVARCHAR(20)),
                               @value, @now
                        WHERE NOT EXISTS (
                            SELECT 1 FROM dbo.alerts
                            WHERE node_id = @node_id
                              AND alert_type = @alert_type
                              AND status IN (N'OPEN', N'ACKNOWLEDGED')
                        );
                    END TRY
                    BEGIN CATCH
                        IF ERROR_NUMBER() NOT IN (2601, 2627)
                            THROW;
                    END CATCH
                END;
            END
            ELSE
            BEGIN
                BEGIN TRY
                    INSERT INTO dbo.alerts (node_id, threshold_id, alert_type, severity, status,
                                            message, metric_value, triggered_at)
                    SELECT @node_id, @threshold_id, @alert_type, N'WARNING', N'OPEN',
                           N'Cảnh báo WARNING: ' + @metric_type + N' = '
                               + CAST(@value AS NVARCHAR(20)) + N' vượt ngưỡng '
                               + CAST(@warning AS NVARCHAR(20)),
                           @value, @now
                    WHERE NOT EXISTS (
                        SELECT 1 FROM dbo.alerts
                        WHERE node_id = @node_id
                          AND alert_type = @alert_type
                          AND status IN (N'OPEN', N'ACKNOWLEDGED')
                    );
                END TRY
                BEGIN CATCH
                    IF ERROR_NUMBER() NOT IN (2601, 2627)
                        THROW;
                END CATCH
            END;
        END;

        IF @own_tran = 1 AND @@TRANCOUNT > 0
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_record_telemetry_batch
    @node_id        INT,
    @metrics_json   NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    IF @metrics_json IS NULL OR ISJSON(@metrics_json) <> 1 OR LEFT(LTRIM(@metrics_json), 1) <> N'['
        THROW 51032, N'metrics_json must be a valid JSON array.', 1;

    DECLARE @now DATETIME2 = SYSUTCDATETIME();
    DECLARE @batch TABLE (
        row_num         INT IDENTITY(1,1) PRIMARY KEY,
        metric_type     NVARCHAR(50) NULL,
        value           FLOAT NULL,
        unit            NVARCHAR(20) NULL,
        collected_at    DATETIME2 NOT NULL,
        metric_type_id  INT NULL,
        canonical_unit  NVARCHAR(20) NULL
    );

    INSERT INTO @batch (metric_type, value, unit, collected_at)
    SELECT j.metric_type,
           j.value,
           j.unit,
           COALESCE(j.collected_at, @now)
    FROM OPENJSON(@metrics_json)
    WITH (
        metric_type     NVARCHAR(50) N'$.metric_type',
        value           FLOAT        N'$.value',
        unit            NVARCHAR(20) N'$.unit',
        collected_at    DATETIME2    N'$.timestamp'
    ) j;

    IF NOT EXISTS (SELECT 1 FROM @batch)
        THROW 51032, N'metrics_json array must not be empty.', 1;

    IF EXISTS (
        SELECT 1 FROM @batch
        WHERE NULLIF(LTRIM(RTRIM(metric_type)), N'') IS NULL
           OR value IS NULL
           OR NULLIF(LTRIM(RTRIM(unit)), N'') IS NULL
    )
        THROW 51032, N'Each batch metric requires metric_type, numeric value, and unit.', 1;

    UPDATE b
    SET b.metric_type_id = mt.id,
        b.canonical_unit = mt.unit
    FROM @batch b
    LEFT JOIN dbo.metric_types mt ON mt.code = b.metric_type;

    IF EXISTS (SELECT 1 FROM @batch WHERE metric_type_id IS NULL)
        THROW 51030, N'Unknown telemetry metric type in batch.', 1;

    IF EXISTS (SELECT 1 FROM @batch WHERE canonical_unit IS NULL OR canonical_unit <> unit)
        THROW 51031, N'Telemetry unit does not match metric type in batch.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51062, N'Node not found.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

    BEGIN TRY
        IF @own_tran = 1
            BEGIN TRANSACTION;

        INSERT INTO dbo.telemetry_metrics (node_id, metric_type_id, value, timestamp)
        SELECT @node_id, metric_type_id, value, collected_at
        FROM @batch;

        DECLARE @inserted_count INT = @@ROWCOUNT;

        ;WITH latest_in_batch AS (
            SELECT metric_type_id,
                   value,
                   collected_at,
                   ROW_NUMBER() OVER (
                       PARTITION BY metric_type_id
                       ORDER BY collected_at DESC, row_num DESC
                   ) AS rn
            FROM @batch
        )
        MERGE dbo.node_latest_metrics AS tgt
        USING (
            SELECT @node_id AS node_id, metric_type_id, value, collected_at
            FROM latest_in_batch
            WHERE rn = 1
        ) AS src
        ON tgt.node_id = src.node_id AND tgt.metric_type_id = src.metric_type_id
        WHEN MATCHED AND src.collected_at >= tgt.timestamp THEN
            UPDATE SET tgt.value = src.value, tgt.timestamp = src.collected_at
        WHEN NOT MATCHED THEN
            INSERT (node_id, metric_type_id, value, timestamp)
            VALUES (src.node_id, src.metric_type_id, src.value, src.collected_at);

        UPDATE dbo.alerts
        SET status = N'RESOLVED',
            resolved_at = @now
        WHERE node_id = @node_id
          AND alert_type = N'NODE_UNAVAILABLE'
          AND status IN (N'OPEN', N'ACKNOWLEDGED');

        -- Đánh giá ngưỡng trên từng loại metric trong lô
        DECLARE @m_type NVARCHAR(50), @m_id INT, @m_val FLOAT, @th_id INT, @warn FLOAT, @crit FLOAT;
        DECLARE batch_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT b.metric_type, b.metric_type_id, MAX(b.value) AS max_val,
                   at.id, at.warning_threshold, at.critical_threshold
            FROM @batch b
            INNER JOIN dbo.alert_thresholds at ON at.metric_type_id = b.metric_type_id AND at.is_active = 1
            GROUP BY b.metric_type, b.metric_type_id, at.id, at.warning_threshold, at.critical_threshold;

        OPEN batch_cur;
        FETCH NEXT FROM batch_cur INTO @m_type, @m_id, @m_val, @th_id, @warn, @crit;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @m_val >= @warn
            BEGIN
                DECLARE @a_type NVARCHAR(50) = @m_type + N'_OVERLOAD';
                IF @m_val >= @crit
                BEGIN
                    IF EXISTS (
                        SELECT 1 FROM dbo.alerts
                        WHERE node_id = @node_id AND alert_type = @a_type
                          AND severity = N'WARNING' AND status IN (N'OPEN', N'ACKNOWLEDGED')
                    )
                    BEGIN
                        UPDATE dbo.alerts
                        SET severity = N'CRITICAL',
                            metric_value = @m_val,
                            message = N'Cảnh báo CRITICAL: ' + @m_type + N' = '
                                      + CAST(@m_val AS NVARCHAR(20)) + N' vượt ngưỡng '
                                      + CAST(@crit AS NVARCHAR(20)),
                            triggered_at = @now
                        WHERE node_id = @node_id AND alert_type = @a_type
                          AND severity = N'WARNING' AND status IN (N'OPEN', N'ACKNOWLEDGED');
                    END
                    ELSE
                    BEGIN
                        BEGIN TRY
                            INSERT INTO dbo.alerts (node_id, threshold_id, alert_type, severity, status, message, metric_value, triggered_at)
                            SELECT @node_id, @th_id, @a_type, N'CRITICAL', N'OPEN',
                                   N'Cảnh báo CRITICAL: ' + @m_type + N' = '
                                       + CAST(@m_val AS NVARCHAR(20)) + N' vượt ngưỡng '
                                       + CAST(@crit AS NVARCHAR(20)),
                                   @m_val, @now
                            WHERE NOT EXISTS (
                                SELECT 1 FROM dbo.alerts
                                WHERE node_id = @node_id AND alert_type = @a_type
                                  AND status IN (N'OPEN', N'ACKNOWLEDGED')
                            );
                        END TRY
                        BEGIN CATCH
                            IF ERROR_NUMBER() NOT IN (2601, 2627) THROW;
                        END CATCH
                    END;
                END
                ELSE
                BEGIN
                    BEGIN TRY
                        INSERT INTO dbo.alerts (node_id, threshold_id, alert_type, severity, status, message, metric_value, triggered_at)
                        SELECT @node_id, @th_id, @a_type, N'WARNING', N'OPEN',
                               N'Cảnh báo WARNING: ' + @m_type + N' = '
                                   + CAST(@m_val AS NVARCHAR(20)) + N' vượt ngưỡng '
                                   + CAST(@warn AS NVARCHAR(20)),
                               @m_val, @now
                        WHERE NOT EXISTS (
                            SELECT 1 FROM dbo.alerts
                            WHERE node_id = @node_id AND alert_type = @a_type
                              AND status IN (N'OPEN', N'ACKNOWLEDGED')
                        );
                    END TRY
                    BEGIN CATCH
                        IF ERROR_NUMBER() NOT IN (2601, 2627) THROW;
                    END CATCH
                END;
            END;
            FETCH NEXT FROM batch_cur INTO @m_type, @m_id, @m_val, @th_id, @warn, @crit;
        END;
        CLOSE batch_cur;
        DEALLOCATE batch_cur;

        -- Cập nhật 1 lần trạng thái node dựa trên tình trạng alert mới nhất
        DECLARE @has_critical BIT = CASE WHEN EXISTS (
            SELECT 1 FROM dbo.alerts WHERE node_id = @node_id AND severity = N'CRITICAL' AND status IN (N'OPEN', N'ACKNOWLEDGED')
        ) THEN 1 ELSE 0 END;
        DECLARE @has_warning BIT = CASE WHEN EXISTS (
            SELECT 1 FROM dbo.alerts WHERE node_id = @node_id AND severity = N'WARNING' AND status IN (N'OPEN', N'ACKNOWLEDGED')
        ) THEN 1 ELSE 0 END;

        UPDATE dbo.nodes
        SET last_ping_at = @now,
            status = CASE
                WHEN status = N'MAINTENANCE' THEN N'MAINTENANCE'
                WHEN @has_critical = 1 THEN N'CRITICAL'
                WHEN @has_warning = 1 THEN N'WARNING'
                ELSE N'ONLINE'
            END
        WHERE id = @node_id;

        IF @own_tran = 1 AND @@TRANCOUNT > 0
            COMMIT TRANSACTION;

        SELECT @inserted_count AS recorded_count, @node_id AS node_id;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 6. LỌC @node_id TẠI SQL & PHÂN TRANG (OFFSET ... FETCH)
-- ═══════════════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE dbo.usp_list_nodes_latest
    @rack_id    INT = NULL,
    @limit      INT = 100,
    @offset     INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @safe_limit INT = CASE WHEN @limit IS NULL OR @limit < 1 THEN 100 WHEN @limit > 500 THEN 500 ELSE @limit END;
    DECLARE @safe_offset INT = CASE WHEN @offset IS NULL OR @offset < 0 THEN 0 ELSE @offset END;

    ;WITH latest AS (
        SELECT node_id,
               MAX(CASE WHEN metric_type = N'cpu_usage_percent' THEN value END) AS cpu_usage_percent,
               MAX(CASE WHEN metric_type = N'memory_usage_percent' THEN value END) AS memory_usage_percent,
               MAX(CASE WHEN metric_type = N'disk_usage_percent' THEN value END) AS disk_usage_percent,
               MAX(CASE WHEN metric_type = N'temperature_celsius' THEN value END) AS temperature_celsius,
               MAX(timestamp) AS collected_at
        FROM dbo.vw_latest_telemetry
        GROUP BY node_id
    )
    SELECT n.id,
           n.name,
           n.hostname,
           n.ip_address,
           n.mac_address,
           rk.id AS rack_id,
           rk.name AS rack_name,
           r.id AS room_id,
           r.name AS room_name,
           s.id AS site_id,
           s.name AS site_name,
           n.rack_position_u,
           n.power_consumption_watts,
           n.status,
           n.last_ping_at,
           l.collected_at,
           l.cpu_usage_percent,
           l.memory_usage_percent,
           l.disk_usage_percent,
           l.temperature_celsius,
           (SELECT COUNT(*) FROM dbo.containers c WHERE c.node_id = n.id) AS container_count,
           (SELECT COUNT(*) FROM dbo.alerts a WHERE a.node_id = n.id AND a.status IN (N'OPEN', N'ACKNOWLEDGED')) AS open_alert_count,
           COALESCE(
               (SELECT TOP (1) m.marker_code FROM dbo.markers m WHERE m.node_id = n.id AND m.marker_type = N'QR' ORDER BY m.id),
               (SELECT TOP (1) m.marker_code FROM dbo.markers m WHERE m.node_id = n.id ORDER BY m.id)
           ) AS primary_marker_code
    FROM dbo.nodes n
    JOIN dbo.racks rk ON rk.id = n.rack_id
    JOIN dbo.rooms r ON r.id = rk.room_id
    JOIN dbo.sites s ON s.id = r.site_id
    LEFT JOIN latest l ON l.node_id = n.id
    WHERE @rack_id IS NULL OR n.rack_id = @rack_id
    ORDER BY s.name, r.name, rk.name, n.name
    OFFSET @safe_offset ROWS FETCH NEXT @safe_limit ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_alerts
    @statuses   NVARCHAR(200) = N'OPEN,ACKNOWLEDGED',
    @node_id    INT = NULL,
    @limit      INT = 100,
    @offset     INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @safe_limit INT = CASE WHEN @limit IS NULL OR @limit < 1 THEN 100 WHEN @limit > 500 THEN 500 ELSE @limit END;
    DECLARE @safe_offset INT = CASE WHEN @offset IS NULL OR @offset < 0 THEN 0 ELSE @offset END;

    SELECT a.id, a.node_id, n.name AS node_name, a.alert_type, a.severity, a.status,
           a.message, a.metric_value, a.triggered_at, a.acknowledged_at
    FROM dbo.alerts a
    JOIN dbo.nodes n ON n.id = a.node_id
    WHERE (@node_id IS NULL OR a.node_id = @node_id)
      AND (
          NULLIF(LTRIM(RTRIM(@statuses)), N'') IS NULL
          OR EXISTS (SELECT 1 FROM STRING_SPLIT(@statuses, N',') st WHERE LTRIM(RTRIM(st.value)) = a.status)
      )
    ORDER BY a.triggered_at DESC, a.id DESC
    OFFSET @safe_offset ROWS FETCH NEXT @safe_limit ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_tickets
    @statuses   NVARCHAR(200) = NULL,
    @node_id    INT = NULL,
    @limit      INT = 100,
    @offset     INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @safe_limit INT = CASE WHEN @limit IS NULL OR @limit < 1 THEN 100 WHEN @limit > 500 THEN 500 ELSE @limit END;
    DECLARE @safe_offset INT = CASE WHEN @offset IS NULL OR @offset < 0 THEN 0 ELSE @offset END;

    SELECT t.id,
           t.alert_id,
           t.node_id,
           n.name AS node_name,
           t.title,
           t.description,
           t.priority,
           t.status,
           t.assigned_to_user_id,
           au.username AS assigned_to_username,
           t.created_by_user_id,
           cu.username AS created_by_username,
           t.created_at,
           t.updated_at,
           cr.status AS closure_status,
           cr.summary AS closure_summary,
           cr.resolution_details AS closure_resolution_details,
           rqu.username AS closure_requested_by_username,
           (SELECT COUNT(*) FROM dbo.ticket_notes tn WHERE tn.ticket_id = t.id) AS note_count
    FROM dbo.tickets t
    JOIN dbo.nodes n ON n.id = t.node_id
    LEFT JOIN dbo.users au ON au.id = t.assigned_to_user_id
    LEFT JOIN dbo.users cu ON cu.id = t.created_by_user_id
    LEFT JOIN dbo.ticket_closure_requests cr ON cr.ticket_id = t.id
    LEFT JOIN dbo.users rqu ON rqu.id = cr.requested_by_user_id
    WHERE (@node_id IS NULL OR t.node_id = @node_id)
      AND (
          NULLIF(LTRIM(RTRIM(@statuses)), N'') IS NULL
          OR EXISTS (SELECT 1 FROM STRING_SPLIT(@statuses, N',') st WHERE LTRIM(RTRIM(st.value)) = t.status)
      )
    ORDER BY t.created_at DESC, t.id DESC
    OFFSET @safe_offset ROWS FETCH NEXT @safe_limit ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_audit_logs
    @limit          INT = 100,
    @target_entity  NVARCHAR(100) = NULL,
    @offset         INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @safe_limit INT = CASE WHEN @limit IS NULL OR @limit < 1 THEN 100 WHEN @limit > 500 THEN 500 ELSE @limit END;
    DECLARE @safe_offset INT = CASE WHEN @offset IS NULL OR @offset < 0 THEN 0 ELSE @offset END;
    DECLARE @filter NVARCHAR(100) = NULLIF(LTRIM(RTRIM(@target_entity)), N'');

    SELECT al.id,
           al.user_id,
           al.username,
           al.action,
           al.target_entity,
           al.target_id,
           al.details_json,
           al.ip_address,
           al.timestamp
    FROM dbo.audit_logs al
    WHERE @filter IS NULL OR al.target_entity = @filter
    ORDER BY al.timestamp DESC, al.id DESC
    OFFSET @safe_offset ROWS FETCH NEXT @safe_limit ROWS ONLY;
END;
GO

PRINT N'=== 22_scale_architecture.sql applied successfully ===';
GO
