USE AR_IMMS;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- 1 + 2. Kiểm tra trùng rồi tạo filtered unique index
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_alerts_one_open' AND object_id = OBJECT_ID(N'dbo.alerts')
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM dbo.alerts
        WHERE status = N'OPEN'
        GROUP BY node_id, alert_type
        HAVING COUNT(*) > 1
    )
    BEGIN
     SELECT node_id, alert_type, COUNT(*) AS so_alert_open, MIN(id) AS id_cu_nhat
        FROM dbo.alerts
        WHERE status = N'OPEN'
        GROUP BY node_id, alert_type
        HAVING COUNT(*) > 1;

        THROW 51040, N'Duplicate OPEN alerts (same node_id + alert_type) exist; resolve the extra ones before creating UX_alerts_one_open.', 1;
    END

    CREATE UNIQUE NONCLUSTERED INDEX UX_alerts_one_open
        ON dbo.alerts (node_id, alert_type)
        WHERE status = N'OPEN';

    PRINT N'SUCCESS: Đã tạo filtered unique index UX_alerts_one_open.';
END
ELSE
    PRINT N'SKIP: UX_alerts_one_open đã tồn tại.';
GO
-- 3. Stored procedure ghi telemetry: ngưỡng từ bảng + chống trùng alert
CREATE OR ALTER PROCEDURE usp_record_telemetry
    @node_id        INT,
    @metric_type    NVARCHAR(50),
    @value          FLOAT,
    @unit           NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @metric_type_id INT, @canonical_unit NVARCHAR(20);

    SELECT @metric_type_id = id, @canonical_unit = unit
    FROM metric_types
    WHERE code = @metric_type;

    IF @metric_type_id IS NULL
        THROW 51030, N'Unknown telemetry metric type.', 1;

    IF @canonical_unit IS NULL OR @canonical_unit <> @unit
        THROW 51031, N'Telemetry unit does not match the metric type.', 1;

    -- Ngưỡng đang bật của metric này (bảng alert_thresholds)
    DECLARE @threshold_id INT, @warning FLOAT, @critical FLOAT;

    SELECT @threshold_id = id, @warning = warning_threshold, @critical = critical_threshold
    FROM alert_thresholds
    WHERE metric_type_id = @metric_type_id AND is_active = 1;

    -- 1. Lưu telemetry
    INSERT INTO telemetry_metrics (node_id, metric_type_id, value, collected_at)
    VALUES (@node_id, @metric_type_id, @value, SYSUTCDATETIME());

    -- 2. Cập nhật last_ping_at; trạng thái node theo ngưỡng trong bảng
    --    (giữ phạm vi cũ: chỉ CPU và nhiệt độ làm đổi trạng thái node)
    UPDATE nodes
    SET last_ping_at = SYSUTCDATETIME(),
        status = CASE
            WHEN @threshold_id IS NOT NULL
                 AND @metric_type IN (N'cpu_usage_percent', N'temperature_celsius')
                 AND @value >= @critical THEN 'CRITICAL'
            WHEN @threshold_id IS NOT NULL
                 AND @metric_type IN (N'cpu_usage_percent', N'temperature_celsius')
                 AND @value >= @warning THEN 'WARNING'
            ELSE status -- giữ nguyên
        END
    WHERE id = @node_id;

    -- 3. Vượt ngưỡng Critical -> tạo alert, tối đa 1 alert đang mở cho mỗi node + loại
    IF @threshold_id IS NOT NULL AND @value >= @critical
    BEGIN
        DECLARE @alert_type NVARCHAR(50) = @metric_type + N'_OVERLOAD';

        BEGIN TRY
            INSERT INTO alerts (node_id, threshold_id, alert_type, severity, status,
                                message, metric_value, triggered_at)
            SELECT @node_id, @threshold_id, @alert_type, N'CRITICAL', N'OPEN',
                   N'Cảnh báo CRITICAL: ' + @metric_type + N' = '
                       + CAST(@value AS NVARCHAR(20)) + N' vượt ngưỡng '
                       + CAST(@critical AS NVARCHAR(20)),
                   @value, SYSUTCDATETIME()
            WHERE NOT EXISTS (
                SELECT 1 FROM alerts
                WHERE node_id = @node_id
                  AND alert_type = @alert_type
                  AND status IN (N'OPEN', N'ACKNOWLEDGED')
            );
        END TRY
        BEGIN CATCH
            -- 2601/2627: request khác vừa tạo alert OPEN (unique index chặn) -> bỏ qua, telemetry đã ghi.
            -- Mọi lỗi khác phải báo lên.
            IF ERROR_NUMBER() NOT IN (2601, 2627)
                THROW;
        END CATCH
    END
END;
GO
SELECT name, is_unique, filter_definition
FROM sys.indexes
WHERE name = N'UX_alerts_one_open' AND object_id = OBJECT_ID(N'dbo.alerts');
GO

PRINT N'=== HQTCSDL-29: alert dùng bảng ngưỡng + chống trùng đã sẵn sàng ===';
GO