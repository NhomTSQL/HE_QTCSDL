-- ============================================================================
-- AR-IMMS: Security, Core Stored Procedures, Audit Immutability & Indexing
-- Rerunnable (idempotent); apply after scripts 01-17.
-- ============================================================================

USE AR_IMMS;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 1. Health check qua Stored Procedure (thay thế SELECT 1 trực tiếp)
-- Test case: EXEC dbo.usp_health_check; -> trả về 1 dòng ok = 1.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE dbo.usp_health_check
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 1 AS ok;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 2. Xác thực Collector Agent qua Stored Procedure + cập nhật heartbeat
-- Test case: truyền SHA-256 của 'demo-node-key-001' -> trả về node_id = 1
--            và cập nhật last_heartbeat_at; key sai -> 0 dòng.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE dbo.usp_authenticate_collector_agent
    @api_key_hash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @agent_id INT;
    DECLARE @node_id INT;

    SELECT TOP (1)
        @agent_id = id,
        @node_id = node_id
    FROM dbo.data_collector_agents
    WHERE api_key_hash = @api_key_hash
      AND status = N'ACTIVE';

    IF @agent_id IS NOT NULL
    BEGIN
        UPDATE dbo.data_collector_agents
        SET last_heartbeat_at = SYSUTCDATETIME(),
            updated_at = SYSUTCDATETIME()
        WHERE id = @agent_id;
    END;

    SELECT @node_id AS node_id;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 3. Nâng cấp usp_record_telemetry:
--    - Kiểm tra metric_type (51030) và unit (51031) trước khi mở transaction
--    - Transaction an toàn với nested transaction (@own_tran)
--    - Tự phục hồi trạng thái node khi metric về dưới ngưỡng hoặc heartbeat về lại
--    - Tự động resolve alert NODE_UNAVAILABLE khi agent gửi telemetry lại
--    - Tạo alert CRITICAL + chống trùng bằng UX_alerts_one_open
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

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

    BEGIN TRY
        IF @own_tran = 1
            BEGIN TRANSACTION;

        -- 1. Lưu telemetry
        INSERT INTO dbo.telemetry_metrics (node_id, metric_type_id, value, timestamp)
        VALUES (@node_id, @metric_type_id, @value, SYSUTCDATETIME());

        -- 2. Nếu node từng mất kết nối, đánh dấu alert NODE_UNAVAILABLE là RESOLVED khi có nhịp tim mới
        UPDATE dbo.alerts
        SET status = N'RESOLVED',
            resolved_at = SYSUTCDATETIME()
        WHERE node_id = @node_id
          AND alert_type = N'NODE_UNAVAILABLE'
          AND status IN (N'OPEN', N'ACKNOWLEDGED');

        -- 3. Cập nhật last_ping_at và tự phục hồi trạng thái node (không ghi đè MAINTENANCE)
        UPDATE dbo.nodes
        SET last_ping_at = SYSUTCDATETIME(),
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

        -- 4. Vượt ngưỡng Warning / Critical -> tạo hoặc nâng cấp alert, chống trùng bằng UX_alerts_one_open
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
                        triggered_at = SYSUTCDATETIME()
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
                               @value, SYSUTCDATETIME()
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
                           @value, SYSUTCDATETIME()
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

-- ═══════════════════════════════════════════════════════════════════
-- 4. Bảo vệ tính bất biến của audit_logs & sửa trg_ticket_status_audit
-- Test case: UPDATE/DELETE trên audit_logs -> ném lỗi 51090.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR ALTER TRIGGER dbo.trg_audit_logs_immutable
ON dbo.audit_logs
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW 51090, N'Audit logs are immutable and cannot be modified or deleted.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_ticket_status_audit
ON dbo.tickets
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @session_actor_id INT = TRY_CAST(SESSION_CONTEXT(N'actor_user_id') AS INT);

    INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
    SELECT actor.actor_id,
           COALESCE(u.username, N'SYSTEM'),
           N'TICKET_STATUS_CHANGED',
           N'TICKET',
           CAST(i.id AS NVARCHAR(50)),
           N'{"old_status":"' + d.status + N'","new_status":"' + i.status + N'"}',
           N'127.0.0.1',
           SYSUTCDATETIME()
    FROM inserted i
    INNER JOIN deleted d ON i.id = d.id
    CROSS APPLY (
        SELECT COALESCE(@session_actor_id, i.assigned_to_user_id, i.created_by_user_id) AS actor_id
    ) actor
    LEFT JOIN dbo.users u ON u.id = actor.actor_id
    WHERE i.status <> d.status;
END;
GO

-- Recompile trg_alert_audit and usp_check_stale_nodes with QUOTED_IDENTIFIER ON
-- (required for INSERT/UPDATE on dbo.alerts due to filtered index UX_alerts_one_open)
CREATE OR ALTER TRIGGER dbo.trg_alert_audit
ON dbo.alerts
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
    SELECT NULL, N'SYSTEM', N'ALERT_TRIGGERED', N'ALERT',
           CAST(i.id AS NVARCHAR(50)),
           N'{"alert_type":"' + STRING_ESCAPE(i.alert_type, 'json') + N'","severity":"' + i.severity
               + N'","node_id":' + CAST(i.node_id AS NVARCHAR(10))
               + N',"metric_value":' + CAST(i.metric_value AS NVARCHAR(20)) + N'}',
           N'127.0.0.1',
           SYSUTCDATETIME()
    FROM inserted i;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_check_stale_nodes
    @stale_timeout_seconds INT = 90
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cutoff DATETIME2 = DATEADD(SECOND, -@stale_timeout_seconds, SYSUTCDATETIME());
    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

    BEGIN TRY
        IF @own_tran = 1
            BEGIN TRANSACTION;

        UPDATE dbo.nodes
        SET status = N'UNAVAILABLE'
        WHERE last_ping_at < @cutoff
          AND status <> N'UNAVAILABLE'
          AND status <> N'MAINTENANCE';

        BEGIN TRY
            INSERT INTO dbo.alerts (node_id, alert_type, severity, status, message, metric_value, triggered_at)
            SELECT n.id, N'NODE_UNAVAILABLE', N'CRITICAL', N'OPEN',
                   N'Mất heartbeat: Node ' + n.name + N' không gửi dữ liệu trong '
                       + CAST(@stale_timeout_seconds AS NVARCHAR(10)) + N' giây',
                   0.0, SYSUTCDATETIME()
            FROM dbo.nodes n
            WHERE n.last_ping_at < @cutoff
              AND n.status = N'UNAVAILABLE'
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.alerts a
                  WHERE a.node_id = n.id
                    AND a.alert_type = N'NODE_UNAVAILABLE'
                    AND a.status IN (N'OPEN', N'ACKNOWLEDGED')
              );
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() NOT IN (2601, 2627)
                THROW;
        END CATCH;

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

-- ═══════════════════════════════════════════════════════════════════
-- 5. Database Role quyền tối thiểu (Least Privilege)
-- ═══════════════════════════════════════════════════════════════════
IF NOT EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = N'db_ar_imms_executor'
      AND type = N'R'
)
BEGIN
    CREATE ROLE db_ar_imms_executor;
END;
GO

GRANT EXECUTE ON SCHEMA::dbo TO db_ar_imms_executor;
DENY UPDATE, DELETE ON dbo.audit_logs TO db_ar_imms_executor;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 6. Covering Index tối ưu truy vấn snapshot và lịch sử telemetry
-- ═══════════════════════════════════════════════════════════════════
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_telemetry_node_metric_time_inc'
      AND object_id = OBJECT_ID(N'dbo.telemetry_metrics')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_telemetry_node_metric_time_inc
        ON dbo.telemetry_metrics (node_id, metric_type_id, timestamp DESC)
        INCLUDE (value);
END;
GO

PRINT N'=== 19_security_and_core_fixes.sql applied successfully ===';
GO
