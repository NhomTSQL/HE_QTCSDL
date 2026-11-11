-- ============================================================================
-- AR-IMMS: Stored Procedures & Triggers cho SQL Server
-- Tận dụng tính năng SQL Server: SP, Trigger, View, Function
-- ============================================================================

USE AR_IMMS;
GO

-- ═══════════════════════════════════════════════════════════════════
-- TRIGGER: Tự động cập nhật updated_at khi UPDATE
-- ═══════════════════════════════════════════════════════════════════
-- Test case: UPDATE một user/node/ticket; expected: updated_at được cập nhật theo UTC.

CREATE OR ALTER TRIGGER trg_users_updated_at ON users
AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE users SET updated_at = SYSUTCDATETIME()
    FROM users u INNER JOIN inserted i ON u.id = i.id;
END;
GO

CREATE OR ALTER TRIGGER trg_nodes_updated_at ON nodes
AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE nodes SET updated_at = SYSUTCDATETIME()
    FROM nodes n INNER JOIN inserted i ON n.id = i.id;
END;
GO

CREATE OR ALTER TRIGGER trg_tickets_updated_at ON tickets
AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE tickets SET updated_at = SYSUTCDATETIME()
    FROM tickets t INNER JOIN inserted i ON t.id = i.id;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- TRIGGER: Audit Log tự động khi Alert được tạo
-- ═══════════════════════════════════════════════════════════════════
-- Test case: INSERT một alert; expected: audit_logs có bản ghi ALERT_TRIGGERED cùng alert ID.

CREATE OR ALTER TRIGGER trg_alert_audit ON alerts
AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
    SELECT NULL, N'SYSTEM', N'ALERT_TRIGGERED', N'ALERT',
           CAST(i.id AS NVARCHAR(50)),
           N'{"alert_type":"' + i.alert_type + N'","severity":"' + i.severity
               + N'","node_id":' + CAST(i.node_id AS NVARCHAR(10))
               + N',"metric_value":' + CAST(i.metric_value AS NVARCHAR(20)) + N'}',
           N'127.0.0.1',
           SYSUTCDATETIME()
    FROM inserted i;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- TRIGGER: Audit Log khi Ticket thay đổi trạng thái
-- ═══════════════════════════════════════════════════════════════════
-- Test case: đổi status của ticket; expected: audit_logs ghi đúng status cũ và mới.

CREATE OR ALTER TRIGGER trg_ticket_status_audit ON tickets
AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    -- Chỉ ghi log khi status thay đổi
    INSERT INTO audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
    SELECT i.assigned_to_user_id,
           (SELECT username FROM users WHERE id = i.assigned_to_user_id),
           N'TICKET_STATUS_CHANGED', N'TICKET',
           CAST(i.id AS NVARCHAR(50)),
           N'{"old_status":"' + d.status + N'","new_status":"' + i.status + N'"}',
           N'127.0.0.1',
           SYSUTCDATETIME()
    FROM inserted i
    INNER JOIN deleted d ON i.id = d.id
    WHERE i.status <> d.status;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- VIEW: Tổng quan Dashboard (Summary)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER VIEW vw_dashboard_summary AS
SELECT
    (SELECT COUNT(*) FROM nodes WHERE status = 'ONLINE') AS active_nodes,
    (SELECT COUNT(*) FROM nodes) AS total_nodes,
    (SELECT AVG(telemetry.value)
     FROM telemetry_metrics telemetry
     INNER JOIN metric_types metric ON metric.id = telemetry.metric_type_id
     WHERE metric.code = 'cpu_usage_percent'
       AND telemetry.timestamp >= DATEADD(MINUTE, -5, SYSUTCDATETIME())) AS avg_cpu_5min,
    (SELECT MAX(telemetry.value)
     FROM telemetry_metrics telemetry
     INNER JOIN metric_types metric ON metric.id = telemetry.metric_type_id
     WHERE metric.code = 'temperature_celsius'
       AND telemetry.timestamp >= DATEADD(MINUTE, -5, SYSUTCDATETIME())) AS max_temp_5min,
    (SELECT COUNT(*) FROM alerts WHERE status = 'OPEN') AS open_alerts,
    (SELECT COUNT(*) FROM tickets WHERE status NOT IN ('CLOSED')) AS active_tickets;
GO

-- ═══════════════════════════════════════════════════════════════════
-- VIEW: Telemetry mới nhất cho mỗi Node (Latest Snapshot)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER VIEW vw_latest_telemetry AS
WITH RankedMetrics AS (
    SELECT
        telemetry.node_id,
        metric.code AS metric_type,
        telemetry.value,
        metric.unit,
        telemetry.timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY telemetry.node_id, telemetry.metric_type_id
            ORDER BY telemetry.timestamp DESC
        ) AS rn
    FROM telemetry_metrics telemetry
    INNER JOIN metric_types metric ON metric.id = telemetry.metric_type_id
)
SELECT node_id, metric_type, value, unit, timestamp
FROM RankedMetrics
WHERE rn = 1;
GO

-- ═══════════════════════════════════════════════════════════════════
-- VIEW: Cây phân cấp Digital Twin (Hierarchy Tree)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER VIEW vw_hierarchy_tree AS
SELECT
    s.id AS site_id, s.name AS site_name, s.code AS site_code,
    r.id AS room_id, r.name AS room_name, r.code AS room_code,
    rk.id AS rack_id, rk.name AS rack_name, rk.code AS rack_code,
    n.id AS node_id, n.name AS node_name, n.hostname,
    n.ip_address, n.status AS node_status,
    n.power_consumption_watts
FROM sites s
LEFT JOIN rooms r ON r.site_id = s.id
LEFT JOIN racks rk ON rk.room_id = r.id
LEFT JOIN nodes n ON n.rack_id = rk.id;
GO

-- ═══════════════════════════════════════════════════════════════════
-- SP: Ghi nhận bản tin Telemetry + kiểm tra ngưỡng tự động
-- ═══════════════════════════════════════════════════════════════════
-- Test case: ghi CPU 95% với unit '%' cho Node hợp lệ; expected: lưu telemetry và tạo alert CRITICAL.
-- Unit sai bị từ chối trước khi ghi; kiểm tra trong database/07_test_normalized_schema.sql.

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

    -- 1. Lưu telemetry
    INSERT INTO telemetry_metrics (node_id, metric_type_id, value, timestamp)
    VALUES (@node_id, @metric_type_id, @value, SYSUTCDATETIME());

    -- 2. Cập nhật last_ping_at trên node
    UPDATE nodes
    SET last_ping_at = SYSUTCDATETIME(),
        status = CASE
            WHEN @metric_type = 'cpu_usage_percent' AND @value >= 90.0 THEN 'CRITICAL'
            WHEN @metric_type = 'cpu_usage_percent' AND @value >= 80.0 THEN 'WARNING'
            WHEN @metric_type = 'temperature_celsius' AND @value >= 80.0 THEN 'CRITICAL'
            WHEN @metric_type = 'temperature_celsius' AND @value >= 65.0 THEN 'WARNING'
            ELSE status -- giữ nguyên
        END
    WHERE id = @node_id;

    -- 3. Kiểm tra ngưỡng Critical → tạo Alert tự động
    DECLARE @critical FLOAT, @warning FLOAT, @threshold_id INT;

    SELECT @threshold_id = id, @critical = critical_threshold, @warning = warning_threshold
    FROM alert_thresholds
    WHERE metric_type_id = @metric_type_id AND is_active = 1;

    IF @threshold_id IS NOT NULL AND @value >= @critical
    BEGIN
        -- Chống trùng: chỉ tạo nếu chưa có alert OPEN cho node + metric này
        IF NOT EXISTS (
            SELECT 1 FROM alerts
            WHERE node_id = @node_id
              AND alert_type = @metric_type + '_OVERLOAD'
              AND status IN ('OPEN', 'ACKNOWLEDGED')
        )
        BEGIN
            INSERT INTO alerts (node_id, threshold_id, alert_type, severity, status,
                                message, metric_value, triggered_at)
            VALUES (@node_id, @threshold_id,
                    @metric_type + '_OVERLOAD',
                    N'CRITICAL', N'OPEN',
                    N'Cảnh báo CRITICAL: ' + @metric_type + N' = '
                        + CAST(@value AS NVARCHAR(20)) + N' vượt ngưỡng '
                        + CAST(@critical AS NVARCHAR(20)),
                    @value, SYSUTCDATETIME());
        END
    END
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- SP: Đánh dấu Node UNAVAILABLE khi mất heartbeat > 90 giây
-- (Gọi định kỳ bởi backend mỗi 15-30 giây)
-- ═══════════════════════════════════════════════════════════════════
-- Test case: đặt last_ping_at quá hạn rồi chạy SP; expected: node chuyển UNAVAILABLE và có alert mở.

CREATE OR ALTER PROCEDURE usp_check_stale_nodes
    @stale_timeout_seconds INT = 90
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cutoff DATETIME2 = DATEADD(SECOND, -@stale_timeout_seconds, SYSUTCDATETIME());

    -- Cập nhật status → UNAVAILABLE
    UPDATE nodes
    SET status = 'UNAVAILABLE'
    WHERE last_ping_at < @cutoff
      AND status <> 'UNAVAILABLE'
      AND status <> 'MAINTENANCE';

    -- Tạo alert cho các node vừa chuyển UNAVAILABLE (chống trùng)
    INSERT INTO alerts (node_id, alert_type, severity, status, message, metric_value, triggered_at)
    SELECT n.id, N'NODE_UNAVAILABLE', N'CRITICAL', N'OPEN',
           N'Mất heartbeat: Node ' + n.name + N' không gửi dữ liệu trong '
               + CAST(@stale_timeout_seconds AS NVARCHAR(10)) + N' giây',
           0.0, SYSUTCDATETIME()
    FROM nodes n
    WHERE n.last_ping_at < @cutoff
      AND n.status = 'UNAVAILABLE'
      AND NOT EXISTS (
          SELECT 1 FROM alerts a
          WHERE a.node_id = n.id
            AND a.alert_type = 'NODE_UNAVAILABLE'
            AND a.status IN ('OPEN', 'ACKNOWLEDGED')
      );
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- SP: Báo cáo PUE (Power Usage Effectiveness)
-- PUE = Tổng điện năng cơ sở / Điện năng thiết bị IT
-- ═══════════════════════════════════════════════════════════════════
-- Test case: gọi SP cho site có node; expected: trả PUE, công suất IT và công suất cơ sở.

CREATE OR ALTER PROCEDURE usp_report_pue
    @site_id INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @total_it_power FLOAT;
    DECLARE @cooling_factor FLOAT = 0.42;  -- Hệ số ước lượng làm mát

    SELECT @total_it_power = SUM(n.power_consumption_watts)
    FROM nodes n
    INNER JOIN racks rk ON n.rack_id = rk.id
    INNER JOIN rooms r ON rk.room_id = r.id
    WHERE r.site_id = @site_id
      AND n.status <> 'UNAVAILABLE';

    IF @total_it_power IS NULL OR @total_it_power = 0
        SET @total_it_power = 1.0;  -- Tránh chia 0

    DECLARE @total_facility_power FLOAT = @total_it_power * (1.0 + @cooling_factor);
    DECLARE @pue FLOAT = @total_facility_power / @total_it_power;

    SELECT
        @pue AS current_pue,
        @total_it_power AS it_power_watts,
        @total_facility_power AS total_facility_watts,
        (@total_it_power * 24.0 / 1000.0) AS it_energy_kwh_per_day,
        (@total_facility_power * 24.0 / 1000.0) AS total_energy_kwh_per_day,
        @cooling_factor AS cooling_overhead_ratio;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- FUNCTION: Tính MTTR (Mean Time To Resolution) trung bình
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER FUNCTION ufn_average_mttr_minutes()
RETURNS FLOAT
AS
BEGIN
    DECLARE @avg_minutes FLOAT;

    SELECT @avg_minutes = AVG(
        DATEDIFF(MINUTE, t.created_at, t.updated_at)
    )
    FROM tickets t
    WHERE t.status = 'CLOSED';

    RETURN ISNULL(@avg_minutes, 0.0);
END;
GO

PRINT N'=== Tạo Triggers, Views, Stored Procedures thành công ===';
GO
