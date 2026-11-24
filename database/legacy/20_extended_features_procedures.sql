-- ============================================================================
-- AR-IMMS: Seed bổ sung cho toàn bộ 25 bảng & Stored Procedures mở rộng
-- Hỗ trợ: Digital Twin 5 cấp, Containers, AR/QR Lookup, Ticket Lifecycle,
--         Ngưỡng cảnh báo, Tài sản & Bảo hành, PUE/Capacity Analytics,
--         Quản trị User & Audit Logs.
-- Rerunnable (idempotent); apply after scripts 01-19.
-- ============================================================================

USE AR_IMMS;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 1. SEED DỮ LIỆU MẪU BỔ SUNG (Idempotent; không chạm marker_coordinates,
--    permissions, role_permissions để giữ tương thích 06_verify_seed_data.sql)
-- ═══════════════════════════════════════════════════════════════════

-- 1a. Containers / Workloads trên 4 Node testbed
INSERT INTO dbo.containers (node_id, container_id, name, image, status, cpu_usage_percent, memory_usage_mb, restarted_count)
SELECT s.node_id, s.container_id, s.name, s.image, s.status, s.cpu_usage_percent, s.memory_usage_mb, s.restarted_count
FROM (VALUES
    (1, N'cnt-alpha01-mssql',   N'ar-imms-sqlserver',      N'mcr.microsoft.com/mssql/server:2022-latest', N'RUNNING', 14.2, 1840.5, 0),
    (1, N'cnt-alpha01-flask',   N'ar-imms-flask-api',      N'python:3.12-slim',                            N'RUNNING',  4.8,  215.0, 0),
    (2, N'cnt-beta01-infer',    N'pytorch-inference-srv',  N'nvcr.io/nvidia/pytorch:24.04-py3',            N'RUNNING', 78.5, 6420.0, 3),
    (2, N'cnt-beta01-triton',   N'triton-model-router',    N'nvcr.io/nvidia/tritonserver:24.04-py3',       N'RESTARTING', 16.3, 1280.0, 5),
    (3, N'cnt-alpha03-web',     N'ar-imms-nextjs-bff',     N'node:22-alpine',                              N'RUNNING',  6.4,  340.0, 0),
    (4, N'cnt-delta04-worker',  N'telemetry-batch-worker', N'python:3.12-slim',                            N'RUNNING',  9.1,  195.0, 1)
) s(node_id, container_id, name, image, status, cpu_usage_percent, memory_usage_mb, restarted_count)
WHERE EXISTS (SELECT 1 FROM dbo.nodes n WHERE n.id = s.node_id)
  AND NOT EXISTS (
      SELECT 1 FROM dbo.containers c
      WHERE c.node_id = s.node_id AND c.container_id = s.container_id
  );
GO

-- 1b. Asset Specs (Thông số phần cứng/HĐH) cho 4 Node
INSERT INTO dbo.asset_specs (node_id, cpu_model, cpu_cores, total_ram_gb, total_storage_gb, os_name, os_version)
SELECT s.node_id, s.cpu_model, s.cpu_cores, s.total_ram_gb, s.total_storage_gb, s.os_name, s.os_version
FROM (VALUES
    (1, N'Intel Xeon Silver 4314', 16,  64.0, 2000.0, N'Ubuntu Server',         N'24.04 LTS'),
    (2, N'AMD EPYC 7443P',         24, 128.0, 4000.0, N'Ubuntu Server',         N'22.04 LTS'),
    (3, N'Intel Xeon E-2388G',      8,  32.0, 1000.0, N'Debian GNU/Linux',      N'12.5'),
    (4, N'AMD Ryzen 9 7950X',      16,  64.0, 2000.0, N'Windows Server 2022',   N'21H2')
) s(node_id, cpu_model, cpu_cores, total_ram_gb, total_storage_gb, os_name, os_version)
WHERE EXISTS (SELECT 1 FROM dbo.nodes n WHERE n.id = s.node_id)
  AND NOT EXISTS (SELECT 1 FROM dbo.asset_specs a WHERE a.node_id = s.node_id);
GO

-- 1c. Asset Network Interfaces (NIC cho mỗi asset_spec)
INSERT INTO dbo.asset_network_interfaces (asset_spec_id, interface_name, mac_address, ipv4_address, speed_mbps, mtu, is_up)
SELECT spec.id, nic.interface_name,
       COALESCE(n.mac_address, N'00:1A:2B:3C:4D:99'),
       CASE WHEN nic.interface_name = N'eth0' THEN n.ip_address
            ELSE REPLACE(n.ip_address, N'192.168.10.', N'10.10.10.') END,
       nic.speed_mbps, 1500, 1
FROM dbo.asset_specs spec
INNER JOIN dbo.nodes n ON n.id = spec.node_id
CROSS JOIN (VALUES (N'eth0', 10000), (N'mgmt0', 1000)) nic(interface_name, speed_mbps)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.asset_network_interfaces existing
    WHERE existing.asset_spec_id = spec.id
      AND existing.interface_name = nic.interface_name
);
GO

-- 1d. Warranty Info (Node 2 sắp hết hạn trong 18 ngày, Node 4 đã hết hạn 5 ngày để test cảnh báo)
INSERT INTO dbo.warranty_info (node_id, vendor, model_number, serial_number, purchase_date, warranty_start, warranty_end, support_contact)
SELECT w.node_id, w.vendor, w.model_number, w.serial_number,
       DATEADD(DAY, w.start_offset_days, SYSUTCDATETIME()),
       DATEADD(DAY, w.start_offset_days, SYSUTCDATETIME()),
       DATEADD(DAY, w.end_offset_days, SYSUTCDATETIME()),
       w.support_contact
FROM (VALUES
    (1, N'Dell Technologies', N'PowerEdge R750',   N'SN-DELL-ALPHA01', -365,  730, N'enterprise-support@dell.example'),
    (2, N'HPE',               N'ProLiant DL385',   N'SN-HPE-BETA01',   -712,   18, N'hpe-care@hpe.example'),
    (3, N'Lenovo',            N'ThinkSystem SR630',N'SN-LNV-ALPHA03', -200,  530, N'datacenter-care@lenovo.example'),
    (4, N'Supermicro',        N'AS-2015A-TR',      N'SN-SMC-DELTA04', -735,   -5, N'rma@supermicro.example')
) w(node_id, vendor, model_number, serial_number, start_offset_days, end_offset_days, support_contact)
WHERE EXISTS (SELECT 1 FROM dbo.nodes n WHERE n.id = w.node_id)
  AND NOT EXISTS (SELECT 1 FROM dbo.warranty_info existing WHERE existing.node_id = w.node_id);
GO

-- 1e. Maintenance Histories mẫu
IF NOT EXISTS (SELECT 1 FROM dbo.maintenance_histories)
BEGIN
    INSERT INTO dbo.maintenance_histories (node_id, ticket_id, maintenance_type, description, performed_by_user_id, performed_at, resolution_notes)
    SELECT 1, NULL, N'PREVENTIVE', N'Vệ sinh bụi quạt tản nhiệt và kiểm tra tiếp xúc cáp nguồn dự phòng.', 3, DATEADD(DAY, -14, SYSUTCDATETIME()), N'Nhiệt độ ổn định ở 50-52C sau bảo dưỡng.'
    WHERE EXISTS (SELECT 1 FROM dbo.nodes WHERE id = 1) AND EXISTS (SELECT 1 FROM dbo.users WHERE id = 3);

    INSERT INTO dbo.maintenance_histories (node_id, ticket_id, maintenance_type, description, performed_by_user_id, performed_at, resolution_notes)
    SELECT 3, NULL, N'INSPECTION', N'Kiểm tra hiệu năng cổng mạng 10GbE và cập nhật firmware NIC.', 3, DATEADD(DAY, -7, SYSUTCDATETIME()), N'Không phát hiện packet loss.'
    WHERE EXISTS (SELECT 1 FROM dbo.nodes WHERE id = 3) AND EXISTS (SELECT 1 FROM dbo.users WHERE id = 3);
END;
GO

-- 1f. Notifications mẫu
IF NOT EXISTS (SELECT 1 FROM dbo.notifications)
BEGIN
    INSERT INTO dbo.notifications (user_id, title, message, type, is_read)
    SELECT u.id, N'Hệ thống AR-IMMS sẵn sàng', N'Đã kích hoạt đồng bộ Digital Twin và cảnh báo tự động.', N'SYSTEM', 0
    FROM dbo.users u
    WHERE u.username IN (N'admin', N'operator', N'technician');
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 2. CẬP NHẬT STORED PROCEDURES HIỆN CÓ (Tương thích ngược + bổ sung cột)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE dbo.usp_list_nodes_latest
AS
BEGIN
    SET NOCOUNT ON;
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
    ORDER BY s.name, r.name, rk.name, n.name;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_acknowledge_alert
    @alert_id INT,
    @user_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.alerts WHERE id = @alert_id)
        THROW 51060, N'Alert not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.alerts WHERE id = @alert_id AND status = N'OPEN')
        THROW 51061, N'Only OPEN alerts can be acknowledged.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        UPDATE dbo.alerts
        SET status = N'ACKNOWLEDGED',
            acknowledged_at = SYSUTCDATETIME(),
            acknowledged_by_user_id = @user_id
        WHERE id = @alert_id;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@user_id, @actor_name, N'ALERT_ACKNOWLEDGED', N'ALERT', CAST(@alert_id AS NVARCHAR(50)),
                N'{"status":"ACKNOWLEDGED"}', N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT id, status, acknowledged_at FROM dbo.alerts WHERE id = @alert_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_tickets
    @statuses NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
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
    WHERE NULLIF(LTRIM(RTRIM(@statuses)), N'') IS NULL
       OR EXISTS (SELECT 1 FROM STRING_SPLIT(@statuses, N',') st WHERE LTRIM(RTRIM(st.value)) = t.status)
    ORDER BY t.created_at DESC, t.id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_update_ticket_status
    @ticket_id INT,
    @new_status NVARCHAR(20),
    @actor_user_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @new_status NOT IN (N'OPEN', N'IN_PROGRESS', N'PENDING_CLOSURE', N'CLOSED')
        THROW 51067, N'Invalid ticket status.', 1;

    DECLARE @current NVARCHAR(20), @alert_id INT;
    SELECT @current = status, @alert_id = alert_id FROM dbo.tickets WHERE id = @ticket_id;
    IF @current IS NULL
        THROW 51065, N'Ticket not found.', 1;

    IF NOT ((@current = N'OPEN' AND @new_status = N'IN_PROGRESS')
         OR (@current = N'IN_PROGRESS' AND @new_status = N'PENDING_CLOSURE')
         OR (@current = N'PENDING_CLOSURE' AND @new_status = N'CLOSED'))
        THROW 51066, N'Invalid ticket status transition.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        IF @actor_user_id IS NOT NULL
            EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = @actor_user_id;

        UPDATE dbo.tickets SET status = @new_status WHERE id = @ticket_id;

        EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = NULL;

        IF @new_status = N'CLOSED' AND @alert_id IS NOT NULL
        BEGIN
            UPDATE dbo.alerts
            SET status = N'RESOLVED',
                resolved_at = SYSUTCDATETIME(),
                resolved_by_user_id = COALESCE(@actor_user_id, resolved_by_user_id)
            WHERE id = @alert_id
              AND status IN (N'OPEN', N'ACKNOWLEDGED');
        END;

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = NULL;
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT id, status, updated_at FROM dbo.tickets WHERE id = @ticket_id;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 3. DIGITAL TWIN 5 CẤP, CONTAINERS & ONBOARDING NODE
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE dbo.usp_list_racks
AS
BEGIN
    SET NOCOUNT ON;
    SELECT rk.id,
           rk.name,
           rk.code,
           rk.unit_capacity,
           rk.total_power_capacity_watts,
           r.id AS room_id,
           r.name AS room_name,
           r.code AS room_code,
           r.floor,
           s.id AS site_id,
           s.name AS site_name,
           s.code AS site_code,
           COUNT(n.id) AS node_count,
           COALESCE(SUM(n.power_consumption_watts), 0.0) AS used_power_watts
    FROM dbo.racks rk
    INNER JOIN dbo.rooms r ON r.id = rk.room_id
    INNER JOIN dbo.sites s ON s.id = r.site_id
    LEFT JOIN dbo.nodes n ON n.rack_id = rk.id
    GROUP BY rk.id, rk.name, rk.code, rk.unit_capacity, rk.total_power_capacity_watts,
             r.id, r.name, r.code, r.floor, s.id, s.name, s.code
    ORDER BY s.name, r.name, rk.name;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_containers
    @node_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.id,
           c.node_id,
           n.name AS node_name,
           n.hostname,
           c.container_id,
           c.name,
           c.image,
           c.status,
           c.cpu_usage_percent,
           c.memory_usage_mb,
           c.restarted_count,
           c.created_at,
           c.updated_at
    FROM dbo.containers c
    INNER JOIN dbo.nodes n ON n.id = c.node_id
    WHERE @node_id IS NULL OR c.node_id = @node_id
    ORDER BY c.node_id, c.name;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_upsert_container_telemetry
    @node_id            INT,
    @container_id       NVARCHAR(100),
    @name               NVARCHAR(100),
    @image              NVARCHAR(255),
    @status             NVARCHAR(20),
    @cpu_usage_percent  FLOAT = 0.0,
    @memory_usage_mb    FLOAT = 0.0,
    @restarted_count    INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51062, N'Node not found.', 1;

    IF @status NOT IN (N'RUNNING', N'STOPPED', N'PAUSED', N'RESTARTING', N'EXITED')
        THROW 51075, N'Invalid container status.', 1;

    IF EXISTS (SELECT 1 FROM dbo.containers WHERE node_id = @node_id AND container_id = @container_id)
    BEGIN
        UPDATE dbo.containers
        SET name = @name,
            image = @image,
            status = @status,
            cpu_usage_percent = @cpu_usage_percent,
            memory_usage_mb = @memory_usage_mb,
            restarted_count = @restarted_count,
            updated_at = SYSUTCDATETIME()
        WHERE node_id = @node_id AND container_id = @container_id;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.containers (node_id, container_id, name, image, status, cpu_usage_percent, memory_usage_mb, restarted_count)
        VALUES (@node_id, @container_id, @name, @image, @status, @cpu_usage_percent, @memory_usage_mb, @restarted_count);
    END;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_restart_container
    @container_db_id    INT,
    @actor_user_id      INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @node_id INT, @container_name NVARCHAR(100);
    SELECT @node_id = node_id, @container_name = name
    FROM dbo.containers
    WHERE id = @container_db_id;

    IF @node_id IS NULL
        THROW 51076, N'Container not found.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        UPDATE dbo.containers
        SET status = N'RUNNING',
            restarted_count = restarted_count + 1,
            updated_at = SYSUTCDATETIME()
        WHERE id = @container_db_id;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'CONTAINER_RESTARTED', N'CONTAINER',
                CAST(@container_db_id AS NVARCHAR(50)),
                N'{"node_id":' + CAST(@node_id AS NVARCHAR(10))
                    + N',"container_name":"' + STRING_ESCAPE(@container_name, 'json') + N'"}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT id, node_id, container_id, name, image, status, cpu_usage_percent, memory_usage_mb, restarted_count, updated_at
    FROM dbo.containers
    WHERE id = @container_db_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_register_node
    @rack_id                    INT,
    @name                       NVARCHAR(100),
    @hostname                   NVARCHAR(100),
    @ip_address                 NVARCHAR(50),
    @mac_address                NVARCHAR(50) = NULL,
    @rack_position_u            INT = 1,
    @power_consumption_watts    FLOAT = 150.0,
    @marker_code                NVARCHAR(100) = NULL,
    @api_key_hash               NVARCHAR(255) = NULL,
    @actor_user_id              INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.racks WHERE id = @rack_id)
        THROW 51070, N'Rack not found.', 1;

    DECLARE @clean_marker NVARCHAR(100) = NULLIF(LTRIM(RTRIM(@marker_code)), N'');
    IF @clean_marker IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.markers WHERE marker_code = @clean_marker)
        THROW 51077, N'Marker code already exists.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');
    DECLARE @new_node_id INT;

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        INSERT INTO dbo.nodes (rack_id, name, hostname, ip_address, mac_address, rack_position_u, power_consumption_watts, status)
        VALUES (@rack_id, @name, @hostname, @ip_address, NULLIF(LTRIM(RTRIM(@mac_address)), N''),
                @rack_position_u, @power_consumption_watts, N'ONLINE');

        SET @new_node_id = CAST(SCOPE_IDENTITY() AS INT);

        IF NULLIF(LTRIM(RTRIM(@api_key_hash)), N'') IS NOT NULL
        BEGIN
            INSERT INTO dbo.data_collector_agents (node_id, agent_version, status, api_key_hash)
            VALUES (@new_node_id, N'1.0.0', N'ACTIVE', @api_key_hash);
        END;

        IF @clean_marker IS NOT NULL
        BEGIN
            INSERT INTO dbo.markers (node_id, marker_type, marker_code)
            VALUES (@new_node_id, N'QR', @clean_marker);
        END;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'NODE_REGISTERED', N'NODE', CAST(@new_node_id AS NVARCHAR(50)),
                N'{"hostname":"' + STRING_ESCAPE(@hostname, 'json') + N'","rack_id":' + CAST(@rack_id AS NVARCHAR(10)) + N'}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @new_node_id AS id;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 4. AR / QR MARKER LOOKUP & QUẢN LÝ MARKER
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE dbo.usp_lookup_node_by_marker
    @marker_code NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @clean NVARCHAR(100) = LTRIM(RTRIM(@marker_code));
    IF @clean LIKE N'arimms:/node/%'
        SET @clean = REPLACE(@clean, N'arimms:/node/', N'arimms://node/');
    DECLARE @node_id INT;
    DECLARE @matched_marker_id INT;

    SELECT TOP (1)
        @node_id = m.node_id,
        @matched_marker_id = m.id
    FROM dbo.markers m
    WHERE m.marker_code = @clean;

    IF @node_id IS NULL
    BEGIN
        SELECT TOP (1) @node_id = n.id
        FROM dbo.nodes n
        WHERE n.hostname = @clean
           OR N'NODE-' + RIGHT(N'00' + CAST(n.id AS NVARCHAR(10)), 2) = @clean
           OR N'NODE-' + CAST(n.id AS NVARCHAR(10)) = @clean;

        SELECT TOP (1) @matched_marker_id = m.id
        FROM dbo.markers m
        WHERE m.node_id = @node_id
        ORDER BY m.id;
    END;

    IF @node_id IS NULL
        THROW 51071, N'Marker or node not found.', 1;

    ;WITH latest AS (
        SELECT node_id,
               MAX(CASE WHEN metric_type = N'cpu_usage_percent' THEN value END) AS cpu_usage_percent,
               MAX(CASE WHEN metric_type = N'memory_usage_percent' THEN value END) AS memory_usage_percent,
               MAX(CASE WHEN metric_type = N'disk_usage_percent' THEN value END) AS disk_usage_percent,
               MAX(CASE WHEN metric_type = N'temperature_celsius' THEN value END) AS temperature_celsius,
               MAX(timestamp) AS collected_at
        FROM dbo.vw_latest_telemetry
        WHERE node_id = @node_id
        GROUP BY node_id
    )
    SELECT n.id AS node_id,
           n.name AS node_name,
           n.hostname,
           n.ip_address,
           n.mac_address,
           n.status,
           n.rack_position_u,
           n.power_consumption_watts,
           n.last_ping_at,
           s.name AS site_name,
           r.name AS room_name,
           rk.name AS rack_name,
           COALESCE(m.marker_code, @clean) AS marker_code,
           COALESCE(m.marker_type, N'QR') AS marker_type,
           mc.x AS coord_x,
           mc.y AS coord_y,
           mc.z AS coord_z,
           l.cpu_usage_percent,
           l.memory_usage_percent,
           l.disk_usage_percent,
           l.temperature_celsius,
           l.collected_at,
           sp.cpu_model,
           sp.cpu_cores,
           sp.total_ram_gb,
           sp.total_storage_gb,
           sp.os_name,
           sp.os_version,
           w.vendor,
           w.model_number,
           w.serial_number,
           w.warranty_end,
           w.support_contact
    FROM dbo.nodes n
    INNER JOIN dbo.racks rk ON rk.id = n.rack_id
    INNER JOIN dbo.rooms r ON r.id = rk.room_id
    INNER JOIN dbo.sites s ON s.id = r.site_id
    LEFT JOIN dbo.markers m ON m.id = @matched_marker_id
    LEFT JOIN dbo.marker_coordinates mc ON mc.marker_id = m.id
    LEFT JOIN latest l ON l.node_id = n.id
    LEFT JOIN dbo.asset_specs sp ON sp.node_id = n.id
    LEFT JOIN dbo.warranty_info w ON w.node_id = n.id
    WHERE n.id = @node_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_manage_marker
    @node_id        INT,
    @marker_type    NVARCHAR(20),
    @marker_code    NVARCHAR(100),
    @actor_user_id  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51062, N'Node not found.', 1;

    IF @marker_type NOT IN (N'QR', N'ARUCO')
        THROW 51078, N'Invalid marker type.', 1;

    DECLARE @clean NVARCHAR(100) = LTRIM(RTRIM(@marker_code));
    IF @clean IS NULL OR @clean = N''
        THROW 51078, N'Marker code is required.', 1;

    IF EXISTS (SELECT 1 FROM dbo.markers WHERE marker_code = @clean AND node_id <> @node_id)
        THROW 51077, N'Marker code already assigned to another node.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.markers WHERE marker_code = @clean AND node_id = @node_id)
        BEGIN
            UPDATE dbo.markers
            SET marker_type = @marker_type,
                updated_at = SYSUTCDATETIME()
            WHERE marker_code = @clean AND node_id = @node_id;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.markers (node_id, marker_type, marker_code)
            VALUES (@node_id, @marker_type, @clean);
        END;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'MARKER_UPDATED', N'NODE', CAST(@node_id AS NVARCHAR(50)),
                N'{"marker_type":"' + @marker_type + N'","marker_code":"' + STRING_ESCAPE(@clean, 'json') + N'"}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT id, node_id, marker_type, marker_code, updated_at
    FROM dbo.markers
    WHERE marker_code = @clean;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 5. QUY TRÌNH TICKET ĐẦY ĐỦ (Assign, Notes, Closure Request & Review)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE dbo.usp_assign_ticket
    @ticket_id              INT,
    @assigned_to_user_id    INT,
    @actor_user_id          INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @title NVARCHAR(200);
    SELECT @title = title FROM dbo.tickets WHERE id = @ticket_id;
    IF @title IS NULL
        THROW 51065, N'Ticket not found.', 1;

    DECLARE @assignee_name NVARCHAR(50);
    SELECT @assignee_name = username FROM dbo.users WHERE id = @assigned_to_user_id AND is_active = 1;
    IF @assignee_name IS NULL
        THROW 51072, N'Assignee user not found or inactive.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        UPDATE dbo.tickets
        SET assigned_to_user_id = @assigned_to_user_id
        WHERE id = @ticket_id;

        INSERT INTO dbo.notifications (user_id, title, message, type)
        VALUES (@assigned_to_user_id,
                N'Phân công ticket #' + CAST(@ticket_id AS NVARCHAR(10)),
                N'Bạn được giao xử lý ticket: ' + @title,
                N'TICKET');

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'TICKET_ASSIGNED', N'TICKET', CAST(@ticket_id AS NVARCHAR(50)),
                N'{"assigned_to_user_id":' + CAST(@assigned_to_user_id AS NVARCHAR(10))
                    + N',"assigned_to_username":"' + STRING_ESCAPE(@assignee_name, 'json') + N'"}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT id, assigned_to_user_id, @assignee_name AS assigned_to_username, updated_at
    FROM dbo.tickets
    WHERE id = @ticket_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_ticket_notes
    @ticket_id INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.tickets WHERE id = @ticket_id)
        THROW 51065, N'Ticket not found.', 1;

    SELECT tn.id,
           tn.ticket_id,
           tn.author_user_id,
           u.username AS author_username,
           u.full_name AS author_full_name,
           tn.note_text,
           tn.created_at
    FROM dbo.ticket_notes tn
    INNER JOIN dbo.users u ON u.id = tn.author_user_id
    WHERE tn.ticket_id = @ticket_id
    ORDER BY tn.created_at ASC, tn.id ASC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_add_ticket_note
    @ticket_id          INT,
    @author_user_id     INT,
    @note_text          NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.tickets WHERE id = @ticket_id)
        THROW 51065, N'Ticket not found.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @author_user_id), N'SYSTEM');
    DECLARE @new_note_id INT;

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        INSERT INTO dbo.ticket_notes (ticket_id, author_user_id, note_text)
        VALUES (@ticket_id, @author_user_id, @note_text);

        SET @new_note_id = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@author_user_id, @actor_name, N'TICKET_NOTE_ADDED', N'TICKET', CAST(@ticket_id AS NVARCHAR(50)),
                N'{"note_id":' + CAST(@new_note_id AS NVARCHAR(10)) + N'}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT tn.id, tn.ticket_id, tn.author_user_id, u.username AS author_username,
           u.full_name AS author_full_name, tn.note_text, tn.created_at
    FROM dbo.ticket_notes tn
    INNER JOIN dbo.users u ON u.id = tn.author_user_id
    WHERE tn.id = @new_note_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_submit_ticket_closure_request
    @ticket_id              INT,
    @requested_by_user_id   INT,
    @summary                NVARCHAR(255),
    @resolution_details     NVARCHAR(MAX),
    @maintenance_type       NVARCHAR(50) = N'CORRECTIVE'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @current_status NVARCHAR(20), @node_id INT;
    SELECT @current_status = status, @node_id = node_id FROM dbo.tickets WHERE id = @ticket_id;

    IF @current_status IS NULL
        THROW 51065, N'Ticket not found.', 1;

    IF @current_status = N'CLOSED'
        THROW 51066, N'Closed ticket cannot submit closure request.', 1;

    IF @maintenance_type NOT IN (N'PREVENTIVE', N'CORRECTIVE', N'EMERGENCY', N'INSPECTION')
        THROW 51079, N'Invalid maintenance type.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @requested_by_user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = @requested_by_user_id;

        IF EXISTS (SELECT 1 FROM dbo.ticket_closure_requests WHERE ticket_id = @ticket_id)
        BEGIN
            UPDATE dbo.ticket_closure_requests
            SET requested_by_user_id = @requested_by_user_id,
                summary = @summary,
                resolution_details = @resolution_details,
                status = N'PENDING',
                reviewed_by_user_id = NULL,
                reviewed_at = NULL
            WHERE ticket_id = @ticket_id;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.ticket_closure_requests (ticket_id, requested_by_user_id, summary, resolution_details, status)
            VALUES (@ticket_id, @requested_by_user_id, @summary, @resolution_details, N'PENDING');
        END;

        IF @current_status <> N'PENDING_CLOSURE'
        BEGIN
            UPDATE dbo.tickets SET status = N'PENDING_CLOSURE' WHERE id = @ticket_id;
        END;

        EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = NULL;

        INSERT INTO dbo.maintenance_histories (node_id, ticket_id, maintenance_type, description, performed_by_user_id, resolution_notes)
        VALUES (@node_id, @ticket_id, @maintenance_type, @summary, @requested_by_user_id, @resolution_details);

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@requested_by_user_id, @actor_name, N'TICKET_CLOSURE_REQUESTED', N'TICKET', CAST(@ticket_id AS NVARCHAR(50)),
                N'{"maintenance_type":"' + @maintenance_type + N'","summary":"' + STRING_ESCAPE(@summary, 'json') + N'"}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = NULL;
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT ticket_id, status, summary, resolution_details, created_at
    FROM dbo.ticket_closure_requests
    WHERE ticket_id = @ticket_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_review_ticket_closure_request
    @ticket_id          INT,
    @reviewer_user_id   INT,
    @decision           NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF @decision NOT IN (N'APPROVED', N'REJECTED')
        THROW 51073, N'Decision must be APPROVED or REJECTED.', 1;

    DECLARE @alert_id INT;
    SELECT @alert_id = alert_id FROM dbo.tickets WHERE id = @ticket_id;
    IF NOT EXISTS (SELECT 1 FROM dbo.tickets WHERE id = @ticket_id)
        THROW 51065, N'Ticket not found.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.ticket_closure_requests WHERE ticket_id = @ticket_id AND status = N'PENDING')
        THROW 51073, N'No pending closure request for this ticket.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @reviewer_user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = @reviewer_user_id;

        UPDATE dbo.ticket_closure_requests
        SET status = @decision,
            reviewed_by_user_id = @reviewer_user_id,
            reviewed_at = SYSUTCDATETIME()
        WHERE ticket_id = @ticket_id;

        IF @decision = N'APPROVED'
        BEGIN
            UPDATE dbo.tickets SET status = N'CLOSED' WHERE id = @ticket_id;
            IF @alert_id IS NOT NULL
            BEGIN
                UPDATE dbo.alerts
                SET status = N'RESOLVED',
                    resolved_at = SYSUTCDATETIME(),
                    resolved_by_user_id = @reviewer_user_id
                WHERE id = @alert_id
                  AND status IN (N'OPEN', N'ACKNOWLEDGED');
            END;
        END
        ELSE
        BEGIN
            UPDATE dbo.tickets SET status = N'IN_PROGRESS' WHERE id = @ticket_id;
        END;

        EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = NULL;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@reviewer_user_id, @actor_name, N'TICKET_CLOSURE_REVIEWED', N'TICKET', CAST(@ticket_id AS NVARCHAR(50)),
                N'{"decision":"' + @decision + N'"}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'actor_user_id', @value = NULL;
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT t.id, t.status AS ticket_status, cr.status AS closure_status, cr.reviewed_at
    FROM dbo.tickets t
    INNER JOIN dbo.ticket_closure_requests cr ON cr.ticket_id = t.id
    WHERE t.id = @ticket_id;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 6. QUẢN LÝ NGƯỠNG CẢNH BÁO
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE dbo.usp_list_alert_thresholds
AS
BEGIN
    SET NOCOUNT ON;
    SELECT at.id,
           at.metric_type_id,
           mt.code AS metric_code,
           mt.unit,
           mt.description,
           at.warning_threshold,
           at.critical_threshold,
           at.duration_seconds,
           at.is_active,
           at.updated_at
    FROM dbo.alert_thresholds at
    INNER JOIN dbo.metric_types mt ON mt.id = at.metric_type_id
    ORDER BY mt.id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_update_alert_threshold
    @metric_type_id     INT,
    @warning_threshold  FLOAT,
    @critical_threshold FLOAT,
    @duration_seconds   INT,
    @is_active          BIT,
    @actor_user_id      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @warning_threshold >= @critical_threshold OR @duration_seconds <= 0
        THROW 51074, N'warning_threshold must be less than critical_threshold and duration_seconds > 0.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.alert_thresholds WHERE metric_type_id = @metric_type_id)
        THROW 51074, N'Alert threshold not found for metric_type_id.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        UPDATE dbo.alert_thresholds
        SET warning_threshold = @warning_threshold,
            critical_threshold = @critical_threshold,
            duration_seconds = @duration_seconds,
            is_active = @is_active,
            updated_at = SYSUTCDATETIME()
        WHERE metric_type_id = @metric_type_id;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'THRESHOLD_UPDATED', N'THRESHOLD', CAST(@metric_type_id AS NVARCHAR(50)),
                N'{"warning":' + CAST(@warning_threshold AS NVARCHAR(20))
                    + N',"critical":' + CAST(@critical_threshold AS NVARCHAR(20))
                    + N',"duration_seconds":' + CAST(@duration_seconds AS NVARCHAR(10))
                    + N',"is_active":' + CAST(CAST(@is_active AS INT) AS NVARCHAR(2)) + N'}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT at.id, at.metric_type_id, mt.code AS metric_code, mt.unit,
           at.warning_threshold, at.critical_threshold, at.duration_seconds, at.is_active, at.updated_at
    FROM dbo.alert_thresholds at
    INNER JOIN dbo.metric_types mt ON mt.id = at.metric_type_id
    WHERE at.metric_type_id = @metric_type_id;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 7. QUẢN LÝ TÀI SẢN, BẢO HÀNH & LỊCH SỬ BẢO TRÌ
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE dbo.usp_list_assets
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH nic_summary AS (
        SELECT asset_spec_id,
               STRING_AGG(CONCAT(interface_name, N' (', COALESCE(ipv4_address, mac_address, N'-'), N')'), N', ') AS nics
        FROM dbo.asset_network_interfaces
        GROUP BY asset_spec_id
    )
    SELECT n.id AS node_id,
           n.name AS node_name,
           n.hostname,
           n.ip_address,
           s.name AS site_name,
           r.name AS room_name,
           rk.name AS rack_name,
           sp.cpu_model,
           sp.cpu_cores,
           sp.total_ram_gb,
           sp.total_storage_gb,
           sp.os_name,
           sp.os_version,
           ns.nics,
           w.vendor,
           w.model_number,
           w.serial_number,
           w.warranty_end,
           w.support_contact,
           DATEDIFF(DAY, SYSUTCDATETIME(), w.warranty_end) AS days_remaining,
           CASE
               WHEN w.warranty_end IS NULL THEN N'UNREGISTERED'
               WHEN DATEDIFF(DAY, SYSUTCDATETIME(), w.warranty_end) < 0 THEN N'EXPIRED'
               WHEN DATEDIFF(DAY, SYSUTCDATETIME(), w.warranty_end) <= 30 THEN N'EXPIRING_SOON'
               ELSE N'ACTIVE'
           END AS warranty_status
    FROM dbo.nodes n
    INNER JOIN dbo.racks rk ON rk.id = n.rack_id
    INNER JOIN dbo.rooms r ON r.id = rk.room_id
    INNER JOIN dbo.sites s ON s.id = r.site_id
    LEFT JOIN dbo.asset_specs sp ON sp.node_id = n.id
    LEFT JOIN nic_summary ns ON ns.asset_spec_id = sp.id
    LEFT JOIN dbo.warranty_info w ON w.node_id = n.id
    ORDER BY n.id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_upsert_asset_warranty
    @node_id            INT,
    @cpu_model          NVARCHAR(100),
    @cpu_cores          INT,
    @total_ram_gb       FLOAT,
    @total_storage_gb   FLOAT,
    @os_name            NVARCHAR(100),
    @os_version         NVARCHAR(50),
    @vendor             NVARCHAR(100),
    @model_number       NVARCHAR(100),
    @serial_number      NVARCHAR(100),
    @warranty_end       DATETIME2 = NULL,
    @support_contact    NVARCHAR(255) = NULL,
    @actor_user_id      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51062, N'Node not found.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.asset_specs WHERE node_id = @node_id)
        BEGIN
            UPDATE dbo.asset_specs
            SET cpu_model = @cpu_model,
                cpu_cores = @cpu_cores,
                total_ram_gb = @total_ram_gb,
                total_storage_gb = @total_storage_gb,
                os_name = @os_name,
                os_version = @os_version,
                updated_at = SYSUTCDATETIME()
            WHERE node_id = @node_id;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.asset_specs (node_id, cpu_model, cpu_cores, total_ram_gb, total_storage_gb, os_name, os_version)
            VALUES (@node_id, @cpu_model, @cpu_cores, @total_ram_gb, @total_storage_gb, @os_name, @os_version);
        END;

        IF EXISTS (SELECT 1 FROM dbo.warranty_info WHERE node_id = @node_id)
        BEGIN
            UPDATE dbo.warranty_info
            SET vendor = @vendor,
                model_number = @model_number,
                serial_number = @serial_number,
                warranty_end = @warranty_end,
                support_contact = @support_contact,
                updated_at = SYSUTCDATETIME()
            WHERE node_id = @node_id;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.warranty_info (node_id, vendor, model_number, serial_number, warranty_end, support_contact)
            VALUES (@node_id, @vendor, @model_number, @serial_number, @warranty_end, @support_contact);
        END;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'ASSET_UPDATED', N'ASSET', CAST(@node_id AS NVARCHAR(50)),
                N'{"vendor":"' + STRING_ESCAPE(@vendor, 'json') + N'","serial_number":"' + STRING_ESCAPE(@serial_number, 'json') + N'"}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @node_id AS node_id, N'updated' AS status;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_maintenance_histories
    @node_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT mh.id,
           mh.node_id,
           n.name AS node_name,
           mh.ticket_id,
           t.title AS ticket_title,
           mh.maintenance_type,
           mh.description,
           mh.performed_by_user_id,
           u.username AS performed_by_username,
           mh.performed_at,
           mh.resolution_notes
    FROM dbo.maintenance_histories mh
    INNER JOIN dbo.nodes n ON n.id = mh.node_id
    INNER JOIN dbo.users u ON u.id = mh.performed_by_user_id
    LEFT JOIN dbo.tickets t ON t.id = mh.ticket_id
    WHERE @node_id IS NULL OR mh.node_id = @node_id
    ORDER BY mh.performed_at DESC, mh.id DESC;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 8. BÁO CÁO XU HƯỚNG, CAPACITY PLANNING & PUE
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE dbo.usp_get_telemetry_history
    @node_id        INT,
    @metric_type    NVARCHAR(50) = N'cpu_usage_percent',
    @limit          INT = 40
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @safe_limit INT = CASE WHEN @limit IS NULL OR @limit < 1 THEN 40 WHEN @limit > 200 THEN 200 ELSE @limit END;

    ;WITH recent AS (
        SELECT TOP (@safe_limit)
               tm.id,
               tm.node_id,
               mt.code AS metric_type,
               mt.unit,
               tm.value,
               tm.timestamp
        FROM dbo.telemetry_metrics tm
        INNER JOIN dbo.metric_types mt ON mt.id = tm.metric_type_id
        WHERE tm.node_id = @node_id
          AND mt.code = @metric_type
        ORDER BY tm.timestamp DESC, tm.id DESC
    )
    SELECT id, node_id, metric_type, unit, value, timestamp
    FROM recent
    ORDER BY timestamp ASC, id ASC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_get_analytics_summary
    @site_id INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @total_it_power FLOAT;
    DECLARE @cooling_factor FLOAT = 0.42;

    SELECT @total_it_power = SUM(n.power_consumption_watts)
    FROM dbo.nodes n
    INNER JOIN dbo.racks rk ON n.rack_id = rk.id
    INNER JOIN dbo.rooms r ON rk.room_id = r.id
    WHERE r.site_id = @site_id
      AND n.status <> N'UNAVAILABLE';

    IF @total_it_power IS NULL OR @total_it_power = 0
        SET @total_it_power = 0.0;

    DECLARE @total_facility_power FLOAT = @total_it_power * (1.0 + @cooling_factor);
    DECLARE @current_pue FLOAT = CASE WHEN @total_it_power > 0 THEN @total_facility_power / @total_it_power ELSE 1.0 + @cooling_factor END;

    SELECT ds.active_nodes,
           ds.total_nodes,
           ds.avg_cpu_5min,
           ds.max_temp_5min,
           ds.open_alerts,
           ds.active_tickets,
           dbo.ufn_average_mttr_minutes() AS avg_mttr_minutes,
           @current_pue AS current_pue,
           @total_it_power AS it_power_watts,
           @total_facility_power AS total_facility_watts,
           (@total_it_power * 24.0 / 1000.0) AS it_energy_kwh_per_day,
           (@total_facility_power * 24.0 / 1000.0) AS total_energy_kwh_per_day,
           (SELECT COUNT(*) FROM dbo.data_collector_agents WHERE status = N'ACTIVE') AS active_collectors,
           (SELECT COUNT(*) FROM dbo.containers) AS total_containers,
           (SELECT COUNT(*) FROM dbo.containers WHERE status = N'RUNNING') AS running_containers,
           (SELECT COUNT(*) FROM dbo.warranty_info WHERE warranty_end IS NOT NULL AND DATEDIFF(DAY, SYSUTCDATETIME(), warranty_end) <= 30) AS warranty_attention_count
    FROM dbo.vw_dashboard_summary ds;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_get_capacity_report
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH latest AS (
        SELECT node_id,
               MAX(CASE WHEN metric_type = N'cpu_usage_percent' THEN value END) AS cpu_usage_percent,
               MAX(CASE WHEN metric_type = N'memory_usage_percent' THEN value END) AS memory_usage_percent,
               MAX(CASE WHEN metric_type = N'disk_usage_percent' THEN value END) AS disk_usage_percent,
               MAX(CASE WHEN metric_type = N'temperature_celsius' THEN value END) AS temperature_celsius
        FROM dbo.vw_latest_telemetry
        GROUP BY node_id
    )
    SELECT s.id AS site_id,
           s.name AS site_name,
           r.id AS room_id,
           r.name AS room_name,
           rk.id AS rack_id,
           rk.name AS rack_name,
           rk.code AS rack_code,
           rk.unit_capacity,
           COUNT(n.id) AS node_count,
           COUNT(n.id) AS used_u,
           rk.total_power_capacity_watts,
           COALESCE(SUM(n.power_consumption_watts), 0.0) AS used_power_watts,
           AVG(l.cpu_usage_percent) AS avg_cpu_percent,
           AVG(l.memory_usage_percent) AS avg_ram_percent,
           AVG(l.disk_usage_percent) AS avg_disk_percent,
           MAX(l.temperature_celsius) AS max_temp_celsius
    FROM dbo.racks rk
    INNER JOIN dbo.rooms r ON r.id = rk.room_id
    INNER JOIN dbo.sites s ON s.id = r.site_id
    LEFT JOIN dbo.nodes n ON n.rack_id = rk.id
    LEFT JOIN latest l ON l.node_id = n.id
    GROUP BY s.id, s.name, r.id, r.name, rk.id, rk.name, rk.code, rk.unit_capacity, rk.total_power_capacity_watts
    ORDER BY s.name, r.name, rk.name;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 9. QUẢN TRỊ USER & AUDIT LOGS (SYSTEM ADMINISTRATOR)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE dbo.usp_list_users
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.id,
           u.username,
           u.email,
           u.full_name,
           u.role_id,
           r.name AS role_name,
           u.is_active,
           u.mfa_enabled,
           u.created_at,
           u.updated_at
    FROM dbo.users u
    INNER JOIN dbo.roles r ON r.id = u.role_id
    ORDER BY u.id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_manage_user
    @user_id        INT = NULL,
    @username       NVARCHAR(50),
    @email          NVARCHAR(100),
    @full_name      NVARCHAR(100),
    @role_name      NVARCHAR(50),
    @is_active      BIT = 1,
    @password_hash  NVARCHAR(255) = NULL,
    @actor_user_id  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @role_id INT = (SELECT id FROM dbo.roles WHERE name = @role_name);
    IF @role_id IS NULL
        THROW 51080, N'Invalid role name.', 1;

    DECLARE @clean_hash NVARCHAR(255) = NULLIF(LTRIM(RTRIM(@password_hash)), N'');
    IF @clean_hash IS NOT NULL
       AND @clean_hash NOT LIKE N'scrypt:%'
       AND @clean_hash NOT LIKE N'pbkdf2:%'
        THROW 51050, N'Invalid password hash format.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');
    DECLARE @target_id INT = @user_id;

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        IF @user_id IS NULL
        BEGIN
            IF @clean_hash IS NULL
                THROW 51050, N'Password hash is required for new user.', 1;

            IF EXISTS (SELECT 1 FROM dbo.users WHERE username = @username OR email = @email)
                THROW 51081, N'Username or email already exists.', 1;

            INSERT INTO dbo.users (username, email, password_hash, full_name, role_id, is_active)
            VALUES (@username, @email, @clean_hash, @full_name, @role_id, @is_active);

            SET @target_id = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id = @user_id)
                THROW 51081, N'User not found.', 1;

            IF EXISTS (SELECT 1 FROM dbo.users WHERE (username = @username OR email = @email) AND id <> @user_id)
                THROW 51081, N'Username or email already exists.', 1;

            UPDATE dbo.users
            SET username = @username,
                email = @email,
                full_name = @full_name,
                role_id = @role_id,
                is_active = @is_active,
                password_hash = COALESCE(@clean_hash, password_hash),
                security_version = security_version + CASE WHEN role_id <> @role_id OR is_active <> @is_active OR @clean_hash IS NOT NULL THEN 1 ELSE 0 END
            WHERE id = @user_id;
        END;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'USER_MANAGED', N'USER', CAST(@target_id AS NVARCHAR(50)),
                N'{"username":"' + STRING_ESCAPE(@username, 'json') + N'","role":"' + @role_name
                    + N'","is_active":' + CAST(CAST(@is_active AS INT) AS NVARCHAR(2)) + N'}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT u.id, u.username, u.email, u.full_name, u.role_id, r.name AS role_name, u.is_active, u.updated_at
    FROM dbo.users u
    INNER JOIN dbo.roles r ON r.id = u.role_id
    WHERE u.id = @target_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_assignable_technicians
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.id,
           u.username,
           u.full_name,
           r.name AS role_name
    FROM dbo.users u
    INNER JOIN dbo.roles r ON r.id = u.role_id
    WHERE u.is_active = 1
      AND r.name IN (N'FIELD_TECHNICIAN', N'SYSTEM_OPERATOR', N'ADMINISTRATOR')
    ORDER BY CASE WHEN r.name = N'FIELD_TECHNICIAN' THEN 0 ELSE 1 END, u.id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_audit_logs
    @limit          INT = 100,
    @target_entity  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @safe_limit INT = CASE WHEN @limit IS NULL OR @limit < 1 THEN 100 WHEN @limit > 500 THEN 500 ELSE @limit END;
    DECLARE @filter NVARCHAR(100) = NULLIF(LTRIM(RTRIM(@target_entity)), N'');

    SELECT TOP (@safe_limit)
           al.id,
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
    ORDER BY al.timestamp DESC, al.id DESC;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 10. QUẢN LÝ HẠ TẦNG (SITE/ROOM/RACK), NODE UPDATE, ALERT LIFECYCLE,
--     NOTIFICATIONS, BÁO CÁO 4 CẤP & DATA COLLECTOR AGENTS
-- ═══════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE dbo.usp_list_sites_and_rooms
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.id AS site_id,
           s.name AS site_name,
           s.code AS site_code,
           s.location AS site_location,
           r.id AS room_id,
           r.name AS room_name,
           r.code AS room_code,
           r.floor AS room_floor
    FROM dbo.sites s
    LEFT JOIN dbo.rooms r ON r.site_id = s.id
    ORDER BY s.name, r.name;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_manage_hierarchy
    @entity_type            NVARCHAR(20),
    @id                     INT = NULL,
    @parent_id              INT = NULL,
    @name                   NVARCHAR(100),
    @code                   NVARCHAR(50),
    @extra_text             NVARCHAR(255) = NULL,
    @unit_capacity          INT = 42,
    @power_capacity_watts   FLOAT = 5000.0,
    @actor_user_id          INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @upper_type NVARCHAR(20) = UPPER(LTRIM(RTRIM(@entity_type)));
    IF @upper_type NOT IN (N'SITE', N'ROOM', N'RACK')
        THROW 51083, N'Invalid hierarchy entity_type.', 1;

    DECLARE @clean_name NVARCHAR(100) = LTRIM(RTRIM(@name));
    DECLARE @clean_code NVARCHAR(50) = LTRIM(RTRIM(@code));
    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');
    DECLARE @target_id INT = @id;

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        IF @upper_type = N'SITE'
        BEGIN
            IF @id IS NULL
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.sites WHERE code = @clean_code)
                    THROW 51084, N'Site code already exists.', 1;
                INSERT INTO dbo.sites (name, code, location)
                VALUES (@clean_name, @clean_code, NULLIF(LTRIM(RTRIM(@extra_text)), N''));
                SET @target_id = CAST(SCOPE_IDENTITY() AS INT);
            END
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.sites WHERE id = @id)
                    THROW 51085, N'Site not found.', 1;
                IF EXISTS (SELECT 1 FROM dbo.sites WHERE code = @clean_code AND id <> @id)
                    THROW 51084, N'Site code already exists.', 1;
                UPDATE dbo.sites
                SET name = @clean_name,
                    code = @clean_code,
                    location = NULLIF(LTRIM(RTRIM(@extra_text)), N''),
                    updated_at = SYSUTCDATETIME()
                WHERE id = @id;
            END;
        END
        ELSE IF @upper_type = N'ROOM'
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.sites WHERE id = @parent_id)
                THROW 51085, N'Parent site not found.', 1;
            IF @id IS NULL
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.rooms WHERE code = @clean_code)
                    THROW 51084, N'Room code already exists.', 1;
                INSERT INTO dbo.rooms (site_id, name, code, floor)
                VALUES (@parent_id, @clean_name, @clean_code, NULLIF(LTRIM(RTRIM(@extra_text)), N''));
                SET @target_id = CAST(SCOPE_IDENTITY() AS INT);
            END
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.rooms WHERE id = @id)
                    THROW 51086, N'Room not found.', 1;
                IF EXISTS (SELECT 1 FROM dbo.rooms WHERE code = @clean_code AND id <> @id)
                    THROW 51084, N'Room code already exists.', 1;
                UPDATE dbo.rooms
                SET site_id = @parent_id,
                    name = @clean_name,
                    code = @clean_code,
                    floor = NULLIF(LTRIM(RTRIM(@extra_text)), N''),
                    updated_at = SYSUTCDATETIME()
                WHERE id = @id;
            END;
        END
        ELSE IF @upper_type = N'RACK'
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.rooms WHERE id = @parent_id)
                THROW 51086, N'Parent room not found.', 1;
            IF @id IS NULL
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.racks WHERE code = @clean_code)
                    THROW 51084, N'Rack code already exists.', 1;
                INSERT INTO dbo.racks (room_id, name, code, unit_capacity, total_power_capacity_watts)
                VALUES (@parent_id, @clean_name, @clean_code, @unit_capacity, @power_capacity_watts);
                SET @target_id = CAST(SCOPE_IDENTITY() AS INT);
            END
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.racks WHERE id = @id)
                    THROW 51070, N'Rack not found.', 1;
                IF EXISTS (SELECT 1 FROM dbo.racks WHERE code = @clean_code AND id <> @id)
                    THROW 51084, N'Rack code already exists.', 1;
                UPDATE dbo.racks
                SET room_id = @parent_id,
                    name = @clean_name,
                    code = @clean_code,
                    unit_capacity = @unit_capacity,
                    total_power_capacity_watts = @power_capacity_watts,
                    updated_at = SYSUTCDATETIME()
                WHERE id = @id;
            END;
        END;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'HIERARCHY_MANAGED', @upper_type, CAST(@target_id AS NVARCHAR(50)),
                N'{"code":"' + STRING_ESCAPE(@clean_code, 'json') + N'","name":"' + STRING_ESCAPE(@clean_name, 'json') + N'"}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @target_id AS id, @upper_type AS entity_type, @clean_code AS code, @clean_name AS name;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_update_node
    @node_id                    INT,
    @rack_id                    INT,
    @name                       NVARCHAR(100),
    @hostname                   NVARCHAR(100),
    @ip_address                 NVARCHAR(50),
    @mac_address                NVARCHAR(50) = NULL,
    @rack_position_u            INT = 1,
    @power_consumption_watts    FLOAT = 150.0,
    @status                     NVARCHAR(20) = N'ONLINE',
    @actor_user_id              INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51062, N'Node not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.racks WHERE id = @rack_id)
        THROW 51070, N'Rack not found.', 1;
    IF @status NOT IN (N'ONLINE', N'WARNING', N'CRITICAL', N'UNAVAILABLE', N'MAINTENANCE')
        THROW 51082, N'Invalid node status.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        UPDATE dbo.nodes
        SET rack_id = @rack_id,
            name = @name,
            hostname = @hostname,
            ip_address = @ip_address,
            mac_address = NULLIF(LTRIM(RTRIM(@mac_address)), N''),
            rack_position_u = @rack_position_u,
            power_consumption_watts = @power_consumption_watts,
            status = @status
        WHERE id = @node_id;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'NODE_UPDATED', N'NODE', CAST(@node_id AS NVARCHAR(50)),
                N'{"rack_id":' + CAST(@rack_id AS NVARCHAR(10))
                    + N',"rack_position_u":' + CAST(@rack_position_u AS NVARCHAR(10))
                    + N',"status":"' + @status + N'"}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT id, rack_id, name, hostname, ip_address, mac_address, rack_position_u, power_consumption_watts, status, updated_at
    FROM dbo.nodes
    WHERE id = @node_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_update_alert_status
    @alert_id       INT,
    @new_status     NVARCHAR(20),
    @actor_user_id  INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @node_id INT, @old_status NVARCHAR(20);
    SELECT @node_id = node_id, @old_status = status FROM dbo.alerts WHERE id = @alert_id;
    IF @node_id IS NULL
        THROW 51060, N'Alert not found.', 1;

    IF @new_status NOT IN (N'ACKNOWLEDGED', N'RESOLVED', N'CLOSED')
        THROW 51061, N'Invalid alert status transition target.', 1;

    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        UPDATE dbo.alerts
        SET status = @new_status,
            acknowledged_at = CASE WHEN @new_status = N'ACKNOWLEDGED' AND acknowledged_at IS NULL THEN SYSUTCDATETIME() ELSE acknowledged_at END,
            acknowledged_by_user_id = CASE WHEN @new_status = N'ACKNOWLEDGED' AND acknowledged_by_user_id IS NULL THEN @actor_user_id ELSE acknowledged_by_user_id END,
            resolved_at = CASE WHEN @new_status IN (N'RESOLVED', N'CLOSED') AND resolved_at IS NULL THEN SYSUTCDATETIME() ELSE resolved_at END,
            resolved_by_user_id = CASE WHEN @new_status IN (N'RESOLVED', N'CLOSED') AND resolved_by_user_id IS NULL THEN @actor_user_id ELSE resolved_by_user_id END
        WHERE id = @alert_id;

        IF @new_status IN (N'RESOLVED', N'CLOSED')
        BEGIN
            UPDATE dbo.nodes
            SET status = N'ONLINE'
            WHERE id = @node_id
              AND status IN (N'WARNING', N'CRITICAL')
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.alerts a
                  WHERE a.node_id = @node_id
                    AND a.status IN (N'OPEN', N'ACKNOWLEDGED')
              );
        END;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'ALERT_STATUS_CHANGED', N'ALERT', CAST(@alert_id AS NVARCHAR(50)),
                N'{"old_status":"' + @old_status + N'","new_status":"' + @new_status + N'"}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT id, node_id, status, acknowledged_at, resolved_at
    FROM dbo.alerts
    WHERE id = @alert_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_notifications
    @user_id    INT,
    @limit      INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @safe_limit INT = CASE WHEN @limit IS NULL OR @limit < 1 THEN 30 WHEN @limit > 100 THEN 100 ELSE @limit END;

    SELECT TOP (@safe_limit)
           id, user_id, title, message, type, is_read, created_at
    FROM dbo.notifications
    WHERE user_id = @user_id
    ORDER BY created_at DESC, id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_mark_notification_read
    @user_id            INT,
    @notification_id    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.notifications
    SET is_read = 1
    WHERE user_id = @user_id
      AND (@notification_id IS NULL OR id = @notification_id)
      AND is_read = 0;

    SELECT COUNT(*) AS unread_count
    FROM dbo.notifications
    WHERE user_id = @user_id
      AND is_read = 0;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_get_hierarchical_report
    @group_by   NVARCHAR(20) = N'NODE',
    @hours      INT = 24
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @lvl NVARCHAR(20) = UPPER(LTRIM(RTRIM(@group_by)));
    IF @lvl NOT IN (N'SITE', N'ROOM', N'RACK', N'NODE')
        THROW 51087, N'group_by must be SITE, ROOM, RACK or NODE.', 1;

    DECLARE @safe_hours INT = CASE WHEN @hours IS NULL OR @hours < 1 THEN 24 WHEN @hours > 720 THEN 720 ELSE @hours END;
    DECLARE @cutoff DATETIME2 = DATEADD(HOUR, -@safe_hours, SYSUTCDATETIME());

    ;WITH node_telemetry AS (
        SELECT tm.node_id,
               AVG(CASE WHEN mt.code = N'cpu_usage_percent' THEN tm.value END) AS avg_cpu,
               MAX(CASE WHEN mt.code = N'cpu_usage_percent' THEN tm.value END) AS max_cpu,
               AVG(CASE WHEN mt.code = N'memory_usage_percent' THEN tm.value END) AS avg_ram,
               AVG(CASE WHEN mt.code = N'disk_usage_percent' THEN tm.value END) AS avg_disk,
               MAX(CASE WHEN mt.code = N'temperature_celsius' THEN tm.value END) AS max_temp,
               COUNT_BIG(*) AS sample_count
        FROM dbo.telemetry_metrics tm
        INNER JOIN dbo.metric_types mt ON mt.id = tm.metric_type_id
        WHERE tm.timestamp >= @cutoff
        GROUP BY tm.node_id
    ),
    node_containers AS (
        SELECT node_id,
               COUNT(*) AS total_containers,
               SUM(CASE WHEN status = N'RUNNING' THEN 1 ELSE 0 END) AS running_containers
        FROM dbo.containers
        GROUP BY node_id
    ),
    node_alerts AS (
        SELECT node_id,
               COUNT(*) AS open_alerts
        FROM dbo.alerts
        WHERE status IN (N'OPEN', N'ACKNOWLEDGED')
        GROUP BY node_id
    ),
    node_tickets AS (
        SELECT node_id,
               COUNT(*) AS open_tickets
        FROM dbo.tickets
        WHERE status <> N'CLOSED'
        GROUP BY node_id
    ),
    base AS (
        SELECT s.id AS site_id, s.name AS site_name,
               r.id AS room_id, r.name AS room_name,
               rk.id AS rack_id, rk.name AS rack_name,
               n.id AS node_id, n.name AS node_name,
               n.power_consumption_watts,
               COALESCE(nt.avg_cpu, NULL) AS avg_cpu,
               COALESCE(nt.max_cpu, NULL) AS max_cpu,
               COALESCE(nt.avg_ram, NULL) AS avg_ram,
               COALESCE(nt.avg_disk, NULL) AS avg_disk,
               COALESCE(nt.max_temp, NULL) AS max_temp,
               COALESCE(nt.sample_count, 0) AS sample_count,
               COALESCE(nc.running_containers, 0) AS running_containers,
               COALESCE(na.open_alerts, 0) AS open_alerts,
               COALESCE(ntk.open_tickets, 0) AS open_tickets
        FROM dbo.sites s
        LEFT JOIN dbo.rooms r ON r.site_id = s.id
        LEFT JOIN dbo.racks rk ON rk.room_id = r.id
        LEFT JOIN dbo.nodes n ON n.rack_id = rk.id
        LEFT JOIN node_telemetry nt ON nt.node_id = n.id
        LEFT JOIN node_containers nc ON nc.node_id = n.id
        LEFT JOIN node_alerts na ON na.node_id = n.id
        LEFT JOIN node_tickets ntk ON ntk.node_id = n.id
    )
    SELECT
        CASE @lvl
            WHEN N'SITE' THEN site_id
            WHEN N'ROOM' THEN room_id
            WHEN N'RACK' THEN rack_id
            ELSE node_id
        END AS group_id,
        CASE @lvl
            WHEN N'SITE' THEN site_name
            WHEN N'ROOM' THEN CONCAT(site_name, N' / ', room_name)
            WHEN N'RACK' THEN CONCAT(site_name, N' / ', room_name, N' / ', rack_name)
            ELSE CONCAT(COALESCE(rack_name, N'-'), N' / ', node_name)
        END AS group_label,
        @lvl AS group_by,
        COUNT(node_id) AS node_count,
        COALESCE(SUM(power_consumption_watts), 0.0) AS total_power_watts,
        SUM(running_containers) AS running_containers,
        SUM(open_alerts) AS open_alerts,
        SUM(open_tickets) AS open_tickets,
        SUM(sample_count) AS sample_count,
        AVG(avg_cpu) AS avg_cpu_percent,
        MAX(max_cpu) AS max_cpu_percent,
        AVG(avg_ram) AS avg_ram_percent,
        AVG(avg_disk) AS avg_disk_percent,
        MAX(max_temp) AS max_temp_celsius
    FROM base
    WHERE (@lvl = N'SITE')
       OR (@lvl = N'ROOM' AND room_id IS NOT NULL)
       OR (@lvl = N'RACK' AND rack_id IS NOT NULL)
       OR (@lvl = N'NODE' AND node_id IS NOT NULL)
    GROUP BY
        CASE @lvl
            WHEN N'SITE' THEN site_id
            WHEN N'ROOM' THEN room_id
            WHEN N'RACK' THEN rack_id
            ELSE node_id
        END,
        CASE @lvl
            WHEN N'SITE' THEN site_name
            WHEN N'ROOM' THEN CONCAT(site_name, N' / ', room_name)
            WHEN N'RACK' THEN CONCAT(site_name, N' / ', room_name, N' / ', rack_name)
            ELSE CONCAT(COALESCE(rack_name, N'-'), N' / ', node_name)
        END
    ORDER BY group_label;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_collector_agents
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.id,
           a.node_id,
           n.name AS node_name,
           n.hostname,
           n.ip_address,
           rk.name AS rack_name,
           a.agent_version,
           a.status,
           a.last_heartbeat_at,
           DATEDIFF(SECOND, a.last_heartbeat_at, SYSUTCDATETIME()) AS seconds_since_heartbeat,
           a.created_at,
           a.updated_at
    FROM dbo.data_collector_agents a
    INNER JOIN dbo.nodes n ON n.id = a.node_id
    INNER JOIN dbo.racks rk ON rk.id = n.rack_id
    ORDER BY a.id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_manage_collector_agent
    @agent_id       INT = NULL,
    @node_id        INT,
    @agent_version  NVARCHAR(50) = N'1.0.0',
    @status         NVARCHAR(20) = N'ACTIVE',
    @api_key_hash   NVARCHAR(255) = NULL,
    @actor_user_id  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51062, N'Node not found.', 1;
    IF @status NOT IN (N'ACTIVE', N'INACTIVE', N'ERROR')
        THROW 51088, N'Invalid agent status.', 1;

    DECLARE @clean_hash NVARCHAR(255) = NULLIF(LTRIM(RTRIM(@api_key_hash)), N'');
    DECLARE @own_tran BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @actor_name NVARCHAR(50) = COALESCE((SELECT username FROM dbo.users WHERE id = @actor_user_id), N'SYSTEM');
    DECLARE @target_id INT = @agent_id;

    BEGIN TRY
        IF @own_tran = 1 BEGIN TRANSACTION;

        IF @agent_id IS NULL
        BEGIN
            IF @clean_hash IS NULL
                THROW 51088, N'API key hash is required when creating an agent.', 1;
            INSERT INTO dbo.data_collector_agents (node_id, agent_version, status, api_key_hash)
            VALUES (@node_id, @agent_version, @status, @clean_hash);
            SET @target_id = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.data_collector_agents WHERE id = @agent_id)
                THROW 51088, N'Collector agent not found.', 1;
            UPDATE dbo.data_collector_agents
            SET node_id = @node_id,
                agent_version = @agent_version,
                status = @status,
                api_key_hash = COALESCE(@clean_hash, api_key_hash),
                updated_at = SYSUTCDATETIME()
            WHERE id = @agent_id;
        END;

        INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
        VALUES (@actor_user_id, @actor_name, N'COLLECTOR_AGENT_MANAGED', N'AGENT', CAST(@target_id AS NVARCHAR(50)),
                N'{"node_id":' + CAST(@node_id AS NVARCHAR(10))
                    + N',"status":"' + @status
                    + N'","key_rotated":' + CASE WHEN @clean_hash IS NOT NULL THEN N'true' ELSE N'false' END + N'}',
                N'127.0.0.1', SYSUTCDATETIME());

        IF @own_tran = 1 AND @@TRANCOUNT > 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT a.id, a.node_id, n.name AS node_name, a.agent_version, a.status, a.last_heartbeat_at, a.updated_at
    FROM dbo.data_collector_agents a
    INNER JOIN dbo.nodes n ON n.id = a.node_id
    WHERE a.id = @target_id;
END;
GO

PRINT N'=== 20_extended_features_procedures.sql applied successfully ===';
GO
