-- AR-IMMS: Vertical-slice procedures for API contracts
-- Run after database/08_telemetry_wide_node_latest_audit_v2.sql
-- Safe to rerun: CREATE OR ALTER + idempotent threshold seeds.
USE AR_IMMS;
GO

-- 1. Ensure thresholds exist for metrics
IF NOT EXISTS (SELECT 1 FROM dbo.alert_thresholds t JOIN dbo.metric_types m ON m.id=t.metric_type_id WHERE m.code=N'cpu_usage_percent')
    INSERT dbo.alert_thresholds(metric_type_id, warning_threshold, critical_threshold, duration_seconds, is_active)
    SELECT id, 80, 90, 0, 1 FROM dbo.metric_types WHERE code=N'cpu_usage_percent';
IF NOT EXISTS (SELECT 1 FROM dbo.alert_thresholds t JOIN dbo.metric_types m ON m.id=t.metric_type_id WHERE m.code=N'memory_usage_percent')
    INSERT dbo.alert_thresholds(metric_type_id, warning_threshold, critical_threshold, duration_seconds, is_active)
    SELECT id, 85, 95, 0, 1 FROM dbo.metric_types WHERE code=N'memory_usage_percent';
IF NOT EXISTS (SELECT 1 FROM dbo.alert_thresholds t JOIN dbo.metric_types m ON m.id=t.metric_type_id WHERE m.code=N'disk_usage_percent')
    INSERT dbo.alert_thresholds(metric_type_id, warning_threshold, critical_threshold, duration_seconds, is_active)
    SELECT id, 85, 95, 0, 1 FROM dbo.metric_types WHERE code=N'disk_usage_percent';
GO

-- 2. usp_authenticate_user: returns password hash for app-side bcrypt verify.
CREATE OR ALTER PROCEDURE dbo.usp_authenticate_user
    @username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.id, u.username, u.password_hash,
           CASE r.name
               WHEN N'ADMINISTRATOR' THEN N'admin'
               WHEN N'SYSTEM_OPERATOR' THEN N'operator'
               WHEN N'FIELD_TECHNICIAN' THEN N'technician'
               ELSE LOWER(r.name)
           END AS role_code,
           u.is_active
    FROM dbo.users u
    JOIN dbo.roles r ON r.id = u.role_id
    WHERE u.username = @username;
END;
GO

-- 3. usp_authenticate_agent: agent key is SHA-256 hex in api_key_hash.
CREATE OR ALTER PROCEDURE dbo.usp_authenticate_agent
    @key_hash CHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (1)
        a.id AS agent_id,
        a.node_id,
        CONVERT(BIT, CASE WHEN a.status = N'ACTIVE' THEN 1 ELSE 0 END) AS is_active
    FROM dbo.data_collector_agents a
    WHERE LOWER(a.api_key_hash) = LOWER(@key_hash);
END;
GO

-- 4. usp_record_telemetry_wide: atomic ingest + node_latest + heartbeat + threshold alerts + audit.
-- Reads thresholds from alert_thresholds (no hard-coded values).
-- Deduplicates: only one OPEN/ACKNOWLEDGED alert per node+threshold.
-- Auto-resolves when metric drops below warning threshold.
CREATE OR ALTER PROCEDURE dbo.usp_record_telemetry_wide
    @node_id INT,
    @collected_at DATETIME2(0),
    @cpu_usage_percent DECIMAL(5,2) = NULL,
    @memory_usage_percent DECIMAL(5,2) = NULL,
    @disk_usage_percent DECIMAL(5,2) = NULL,
    @temperature_celsius DECIMAL(6,2) = NULL,
    @network_in_bytes BIGINT = NULL,
    @network_out_bytes BIGINT = NULL,
    @uptime_seconds BIGINT = NULL,
    @process_count INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51050, N'Unknown node.', 1;
    IF @collected_at IS NULL
        THROW 51051, N'collected_at is required.', 1;
    IF (@cpu_usage_percent IS NOT NULL AND @cpu_usage_percent NOT BETWEEN 0 AND 100)
       OR (@memory_usage_percent IS NOT NULL AND @memory_usage_percent NOT BETWEEN 0 AND 100)
       OR (@disk_usage_percent IS NOT NULL AND @disk_usage_percent NOT BETWEEN 0 AND 100)
        THROW 51052, N'Percentage metrics must be between 0 and 100.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Insert telemetry row
        INSERT INTO dbo.telemetry_wide (
            node_id, collected_at, cpu_usage_percent, memory_usage_percent,
            disk_usage_percent, temperature_celsius, network_in_bytes,
            network_out_bytes, uptime_seconds, process_count
        ) VALUES (
            @node_id, @collected_at, @cpu_usage_percent, @memory_usage_percent,
            @disk_usage_percent, @temperature_celsius, @network_in_bytes,
            @network_out_bytes, @uptime_seconds, @process_count
        );
        DECLARE @telemetry_id BIGINT = CONVERT(BIGINT, SCOPE_IDENTITY());

        -- Upsert node_latest (MERGE keeps latest collected_at)
        MERGE dbo.node_latest WITH (HOLDLOCK) AS target
        USING (
            SELECT @node_id AS node_id, @telemetry_id AS telemetry_id, @collected_at AS collected_at,
                   @cpu_usage_percent AS cpu_usage_percent, @memory_usage_percent AS memory_usage_percent,
                   @disk_usage_percent AS disk_usage_percent, @temperature_celsius AS temperature_celsius,
                   @network_in_bytes AS network_in_bytes, @network_out_bytes AS network_out_bytes,
                   @uptime_seconds AS uptime_seconds, @process_count AS process_count
        ) AS src ON target.node_id = src.node_id
        WHEN MATCHED AND src.collected_at >= target.collected_at THEN
            UPDATE SET telemetry_id=src.telemetry_id, collected_at=src.collected_at,
                cpu_usage_percent=src.cpu_usage_percent, memory_usage_percent=src.memory_usage_percent,
                disk_usage_percent=src.disk_usage_percent, temperature_celsius=src.temperature_celsius,
                network_in_bytes=src.network_in_bytes, network_out_bytes=src.network_out_bytes,
                uptime_seconds=src.uptime_seconds, process_count=src.process_count
        WHEN NOT MATCHED THEN
            INSERT (node_id, telemetry_id, collected_at, cpu_usage_percent, memory_usage_percent,
                    disk_usage_percent, temperature_celsius, network_in_bytes, network_out_bytes,
                    uptime_seconds, process_count)
            VALUES (src.node_id, src.telemetry_id, src.collected_at, src.cpu_usage_percent,
                    src.memory_usage_percent, src.disk_usage_percent, src.temperature_celsius,
                    src.network_in_bytes, src.network_out_bytes, src.uptime_seconds, src.process_count);

        -- Heartbeat
        UPDATE dbo.data_collector_agents SET last_heartbeat_at=SYSUTCDATETIME(), updated_at=SYSUTCDATETIME()
        WHERE node_id = @node_id AND status = N'ACTIVE';
        UPDATE dbo.nodes SET last_ping_at = SYSUTCDATETIME() WHERE id = @node_id;

        -- Threshold evaluation: iterate percentage metrics with active thresholds
        DECLARE @mc NVARCHAR(50), @mv FLOAT, @tid INT, @tw FLOAT, @tc FLOAT, @sv NVARCHAR(20);
        DECLARE m_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT code, val FROM (VALUES
                (N'cpu_usage_percent', CONVERT(FLOAT, @cpu_usage_percent)),
                (N'memory_usage_percent', CONVERT(FLOAT, @memory_usage_percent)),
                (N'disk_usage_percent', CONVERT(FLOAT, @disk_usage_percent))
            ) v(code, val) WHERE val IS NOT NULL;
        OPEN m_cur;
        FETCH NEXT FROM m_cur INTO @mc, @mv;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @tid = NULL; SET @tw = NULL; SET @tc = NULL;
            SELECT @tid=t.id, @tw=t.warning_threshold, @tc=t.critical_threshold
            FROM dbo.alert_thresholds t JOIN dbo.metric_types m ON m.id=t.metric_type_id
            WHERE m.code = @mc AND t.is_active = 1;

            IF @tid IS NOT NULL AND @mv >= @tw
            BEGIN
                SET @sv = CASE WHEN @mv >= @tc THEN N'CRITICAL' ELSE N'WARNING' END;
                IF NOT EXISTS (
                    SELECT 1 FROM dbo.alerts WITH (UPDLOCK, HOLDLOCK)
                    WHERE node_id=@node_id AND threshold_id=@tid AND status IN (N'OPEN',N'ACKNOWLEDGED')
                )
                    INSERT dbo.alerts(node_id, threshold_id, alert_type, severity, status, message, metric_value, triggered_at)
                    VALUES(@node_id, @tid, UPPER(@mc), @sv, N'OPEN', @mc+N' crossed threshold', @mv, SYSUTCDATETIME());
                ELSE
                    UPDATE dbo.alerts SET severity=@sv, metric_value=@mv
                    WHERE node_id=@node_id AND threshold_id=@tid AND status IN (N'OPEN',N'ACKNOWLEDGED');
            END
            ELSE IF @tid IS NOT NULL
                UPDATE dbo.alerts SET status=N'RESOLVED', resolved_at=SYSUTCDATETIME()
                WHERE node_id=@node_id AND threshold_id=@tid AND status IN (N'OPEN',N'ACKNOWLEDGED');

            FETCH NEXT FROM m_cur INTO @mc, @mv;
        END;
        CLOSE m_cur; DEALLOCATE m_cur;

        -- Derive node status from active alerts
        DECLARE @ns NVARCHAR(20) = N'ONLINE';
        IF EXISTS (SELECT 1 FROM dbo.alerts WHERE node_id=@node_id AND status IN (N'OPEN',N'ACKNOWLEDGED') AND severity=N'CRITICAL')
            SET @ns = N'CRITICAL';
        ELSE IF EXISTS (SELECT 1 FROM dbo.alerts WHERE node_id=@node_id AND status IN (N'OPEN',N'ACKNOWLEDGED') AND severity=N'WARNING')
            SET @ns = N'WARNING';
        UPDATE dbo.nodes SET status = CASE WHEN status=N'MAINTENANCE' THEN status ELSE @ns END WHERE id=@node_id;

        -- Audit
        INSERT dbo.audit_logs(user_id,username,action,target_entity,target_id,details_json,ip_address,event_type,correlation_id)
        VALUES(NULL,N'SYSTEM',N'TELEMETRY_WIDE_RECORDED',N'NODE',CONVERT(NVARCHAR(50),@node_id),
               N'{"telemetry_id":'+CONVERT(NVARCHAR(30),@telemetry_id)+N'}',NULL,N'TELEMETRY_WIDE_RECORDED',NEWID());

        COMMIT TRANSACTION;
        SELECT @telemetry_id AS telemetry_id;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local','m_cur') >= 0 CLOSE m_cur;
        IF CURSOR_STATUS('local','m_cur') > -3 DEALLOCATE m_cur;
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- 5. usp_list_nodes_latest: projection matching GET /api/nodes.
CREATE OR ALTER PROCEDURE dbo.usp_list_nodes_latest
AS
BEGIN
    SET NOCOUNT ON;
    SELECT n.id, n.name, rk.name AS rack_name, rm.name AS room_name, s.name AS site_name,
           n.status, n.last_ping_at, l.collected_at, l.cpu_usage_percent, l.memory_usage_percent, l.disk_usage_percent
    FROM dbo.nodes n
    LEFT JOIN dbo.racks rk ON rk.id = n.rack_id
    LEFT JOIN dbo.rooms rm ON rm.id = rk.room_id
    LEFT JOIN dbo.sites s ON s.id = rm.site_id
    LEFT JOIN dbo.node_latest l ON l.node_id = n.id
    ORDER BY s.name, rm.name, rk.name, n.name;
END;
GO

-- 6. usp_list_alerts: comma-separated status filter.
CREATE OR ALTER PROCEDURE dbo.usp_list_alerts
    @statuses NVARCHAR(100) = N'OPEN,ACKNOWLEDGED'
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.id, a.node_id, n.name AS node_name, a.alert_type, a.severity,
           a.status, a.message, a.metric_value, a.triggered_at
    FROM dbo.alerts a JOIN dbo.nodes n ON n.id = a.node_id
    WHERE @statuses IS NULL OR EXISTS (
        SELECT 1 FROM STRING_SPLIT(@statuses, N',') x WHERE LTRIM(RTRIM(x.value)) = a.status
    )
    ORDER BY a.triggered_at DESC, a.id DESC;
END;
GO

-- 7. usp_check_stale_nodes: marks stale nodes UNAVAILABLE + deduplicated outage alert.
CREATE OR ALTER PROCEDURE dbo.usp_check_stale_nodes
    @stale_timeout_seconds INT = 90
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @stale_timeout_seconds <= 0 THROW 51053, N'Timeout must be positive.', 1;
    DECLARE @cutoff DATETIME2(0) = DATEADD(SECOND, -@stale_timeout_seconds, SYSUTCDATETIME());
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE dbo.nodes SET status = N'UNAVAILABLE'
        WHERE last_ping_at < @cutoff AND status NOT IN (N'UNAVAILABLE', N'MAINTENANCE');

        INSERT dbo.alerts(node_id, alert_type, severity, status, message, metric_value, triggered_at)
        SELECT n.id, N'NODE_UNAVAILABLE', N'CRITICAL', N'OPEN', N'Node heartbeat is stale', 0, SYSUTCDATETIME()
        FROM dbo.nodes n
        WHERE n.status = N'UNAVAILABLE' AND n.last_ping_at < @cutoff
          AND NOT EXISTS (
              SELECT 1 FROM dbo.alerts a
              WHERE a.node_id = n.id AND a.alert_type = N'NODE_UNAVAILABLE' AND a.status IN (N'OPEN', N'ACKNOWLEDGED')
          );
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
-- 8. Demo credentials for local development only.
-- Password: demo123. Agent key: arimms-demo-agent-key-2026.
-- Replace both values before any shared or production deployment.
DECLARE @demo_password_hash NVARCHAR(255) = N'$2a$10$N5mNnBfguTqnp380tUCG3e5mP83J5pKjHleE9s/t96XUaHFwhdPva';
UPDATE dbo.users SET password_hash=@demo_password_hash WHERE username IN (N'admin',N'operator',N'technician') AND password_hash LIKE N'%placeholder%';
DECLARE @demo_agent_hash NVARCHAR(255) = N'749fc7b232c40b3e837dcfe8e9c6912e646a4a57bcfd11738424af1f11c646bc';
IF EXISTS (SELECT 1 FROM dbo.data_collector_agents WHERE node_id=1 AND (api_key_hash IS NULL OR api_key_hash LIKE N'%placeholder%'))
    UPDATE dbo.data_collector_agents SET api_key_hash=@demo_agent_hash, status=N'ACTIVE' WHERE node_id=1 AND (api_key_hash IS NULL OR api_key_hash LIKE N'%placeholder%');
ELSE IF NOT EXISTS (SELECT 1 FROM dbo.data_collector_agents WHERE node_id=1)
    INSERT dbo.data_collector_agents(node_id, agent_version, status, api_key_hash)
    VALUES(1, N'1.0.0-demo', N'ACTIVE', @demo_agent_hash);

PRINT N'=== 09_api_vertical_slice: all procedures ready ===';
GO
