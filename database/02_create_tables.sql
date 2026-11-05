-- ============================================================================
-- AR-IMMS: Schema Tables cho SQL Server
-- T-SQL schema cho SQL Server
-- 25 bảng: roles, permissions, role_permissions, users, notifications,
--          sites, rooms, racks, nodes,
--          containers, markers, data_collector_agents, telemetry_metrics,
--          alert_thresholds, alerts, tickets, ticket_notes,
--          ticket_closure_requests, warranty_info, asset_specs,
--          asset_network_interfaces, marker_coordinates, metric_types,
--          maintenance_histories, audit_logs
-- ============================================================================

USE AR_IMMS;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 1. NHÓM NGƯỜI DÙNG & PHÂN QUYỀN (User & RBAC)
-- ═══════════════════════════════════════════════════════════════════

IF OBJECT_ID(N'dbo.roles', N'U') IS NULL
BEGIN
CREATE TABLE roles (
    id              INT IDENTITY(1,1)   PRIMARY KEY,
    name            NVARCHAR(50)        NOT NULL UNIQUE,
    description     NVARCHAR(255)       NULL
);
END;
GO

-- Permission codes are catalog rows so roles can share them without JSON arrays.
IF OBJECT_ID(N'dbo.permissions', N'U') IS NULL
BEGIN
CREATE TABLE permissions (
    id              INT IDENTITY(1,1)   PRIMARY KEY,
    code            NVARCHAR(100)       NOT NULL UNIQUE,
    description     NVARCHAR(255)       NULL
);
END;
GO

IF OBJECT_ID(N'dbo.role_permissions', N'U') IS NULL
BEGIN
CREATE TABLE role_permissions (
    role_id         INT                 NOT NULL,
    permission_id   INT                 NOT NULL,

    CONSTRAINT PK_role_permissions PRIMARY KEY (role_id, permission_id),
    CONSTRAINT FK_role_permissions_role FOREIGN KEY (role_id)
        REFERENCES roles(id) ON DELETE CASCADE,
    CONSTRAINT FK_role_permissions_permission FOREIGN KEY (permission_id)
        REFERENCES permissions(id) ON DELETE CASCADE
);
END;
GO

IF OBJECT_ID(N'dbo.users', N'U') IS NULL
BEGIN
CREATE TABLE users (
    id              INT IDENTITY(1,1)   PRIMARY KEY,
    username        NVARCHAR(50)        NOT NULL UNIQUE,
    email           NVARCHAR(100)       NOT NULL UNIQUE,
    password_hash   NVARCHAR(255)       NOT NULL,
    full_name       NVARCHAR(100)       NOT NULL,
    role_id         INT                 NOT NULL,
    is_active       BIT                 NOT NULL DEFAULT 1,
    created_at      DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_users_role FOREIGN KEY (role_id) REFERENCES roles(id)
);
END;
GO

IF OBJECT_ID(N'dbo.notifications', N'U') IS NULL
BEGIN
CREATE TABLE notifications (
    id              INT IDENTITY(1,1)   PRIMARY KEY,
    user_id         INT                 NOT NULL,
    title           NVARCHAR(150)       NOT NULL,
    message         NVARCHAR(MAX)       NOT NULL,
    type            NVARCHAR(50)        NOT NULL DEFAULT 'SYSTEM',
    is_read         BIT                 NOT NULL DEFAULT 0,
    created_at      DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_notifications_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
);
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 2. NHÓM PHÂN CẤP HẠ TẦNG DIGITAL TWIN (Hierarchy)
--    Site → Room → Rack → Node → Container
-- ═══════════════════════════════════════════════════════════════════

IF OBJECT_ID(N'dbo.sites', N'U') IS NULL
BEGIN
CREATE TABLE sites (
    id              INT IDENTITY(1,1)   PRIMARY KEY,
    name            NVARCHAR(100)       NOT NULL,
    code            NVARCHAR(50)        NOT NULL UNIQUE,
    location        NVARCHAR(255)       NULL,
    description     NVARCHAR(MAX)       NULL,
    created_at      DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME()
);
END;
GO

IF OBJECT_ID(N'dbo.rooms', N'U') IS NULL
BEGIN
CREATE TABLE rooms (
    id              INT IDENTITY(1,1)   PRIMARY KEY,
    site_id         INT                 NOT NULL,
    name            NVARCHAR(100)       NOT NULL,
    code            NVARCHAR(50)        NOT NULL UNIQUE,
    floor           NVARCHAR(50)        NULL,
    description     NVARCHAR(MAX)       NULL,
    created_at      DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_rooms_site FOREIGN KEY (site_id)
        REFERENCES sites(id) ON DELETE CASCADE
);
END;
GO

IF OBJECT_ID(N'dbo.racks', N'U') IS NULL
BEGIN
CREATE TABLE racks (
    id                          INT IDENTITY(1,1) PRIMARY KEY,
    room_id                     INT               NOT NULL,
    name                        NVARCHAR(100)     NOT NULL,
    code                        NVARCHAR(50)      NOT NULL UNIQUE,
    unit_capacity               INT               NOT NULL DEFAULT 42,
    total_power_capacity_watts  FLOAT             NOT NULL DEFAULT 5000.0,
    created_at                  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at                  DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_racks_room FOREIGN KEY (room_id)
        REFERENCES rooms(id) ON DELETE CASCADE
);
END;
GO

IF OBJECT_ID(N'dbo.nodes', N'U') IS NULL
BEGIN
CREATE TABLE nodes (
    id                      INT IDENTITY(1,1) PRIMARY KEY,
    rack_id                 INT               NOT NULL,
    name                    NVARCHAR(100)     NOT NULL,
    hostname                NVARCHAR(100)     NOT NULL,
    ip_address              NVARCHAR(50)      NOT NULL,
    mac_address             NVARCHAR(50)      NULL,
    status                  NVARCHAR(20)      NOT NULL DEFAULT 'ONLINE',
    rack_position_u         INT               NOT NULL DEFAULT 1,
    power_consumption_watts FLOAT             NOT NULL DEFAULT 150.0,
    last_ping_at            DATETIME2         NULL DEFAULT SYSUTCDATETIME(),
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_nodes_rack FOREIGN KEY (rack_id)
        REFERENCES racks(id) ON DELETE CASCADE,

    CONSTRAINT CK_nodes_status CHECK (
        status IN ('ONLINE', 'WARNING', 'CRITICAL', 'UNAVAILABLE', 'MAINTENANCE')
    )
);
END;
GO

IF OBJECT_ID(N'dbo.containers', N'U') IS NULL
BEGIN
CREATE TABLE containers (
    id                  INT IDENTITY(1,1) PRIMARY KEY,
    node_id             INT               NOT NULL,
    container_id        NVARCHAR(100)     NOT NULL,
    name                NVARCHAR(100)     NOT NULL,
    image               NVARCHAR(255)     NOT NULL,
    status              NVARCHAR(20)      NOT NULL DEFAULT 'RUNNING',
    cpu_usage_percent   FLOAT             NOT NULL DEFAULT 0.0,
    memory_usage_mb     FLOAT             NOT NULL DEFAULT 0.0,
    restarted_count     INT               NOT NULL DEFAULT 0,
    created_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_containers_node FOREIGN KEY (node_id)
        REFERENCES nodes(id) ON DELETE CASCADE,

    CONSTRAINT CK_containers_status CHECK (
        status IN ('RUNNING', 'STOPPED', 'PAUSED', 'RESTARTING', 'EXITED')
    )
);
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 3. NHÓM AR MARKER & COLLECTOR AGENT
-- ═══════════════════════════════════════════════════════════════════

IF OBJECT_ID(N'dbo.markers', N'U') IS NULL
BEGIN
CREATE TABLE markers (
    id                      INT IDENTITY(1,1) PRIMARY KEY,
    node_id                 INT               NOT NULL,
    marker_type             NVARCHAR(20)      NOT NULL DEFAULT 'ARUCO',
    marker_code             NVARCHAR(100)     NOT NULL UNIQUE,
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_markers_node FOREIGN KEY (node_id)
        REFERENCES nodes(id) ON DELETE CASCADE,

    CONSTRAINT CK_markers_type CHECK (
        marker_type IN ('QR', 'ARUCO')
    )
);
END;
GO

-- A separate one-to-one relation stores the three atomic coordinate axes.
IF OBJECT_ID(N'dbo.marker_coordinates', N'U') IS NULL
BEGIN
CREATE TABLE marker_coordinates (
    marker_id       INT                 PRIMARY KEY,
    x               FLOAT               NULL,
    y               FLOAT               NULL,
    z               FLOAT               NULL,

    CONSTRAINT FK_marker_coordinates_marker FOREIGN KEY (marker_id)
        REFERENCES markers(id) ON DELETE CASCADE,
    CONSTRAINT CK_marker_coordinates_complete CHECK (
        (x IS NULL AND y IS NULL AND z IS NULL)
        OR (x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL)
    )
);
END;
GO

IF OBJECT_ID(N'dbo.data_collector_agents', N'U') IS NULL
BEGIN
CREATE TABLE data_collector_agents (
    id                  INT IDENTITY(1,1) PRIMARY KEY,
    node_id             INT               NOT NULL,
    agent_version       NVARCHAR(50)      NOT NULL,
    status              NVARCHAR(20)      NOT NULL DEFAULT 'ACTIVE',
    api_key_hash        NVARCHAR(255)     NULL,
    last_heartbeat_at   DATETIME2         NULL DEFAULT SYSUTCDATETIME(),
    created_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_agents_node FOREIGN KEY (node_id)
        REFERENCES nodes(id) ON DELETE CASCADE,

    CONSTRAINT CK_agents_status CHECK (
        status IN ('ACTIVE', 'INACTIVE', 'ERROR')
    )
);
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 4. NHÓM TELEMETRY & CẢNH BÁO (Telemetry & Alerting)
-- ═══════════════════════════════════════════════════════════════════

-- Unit belongs to a metric definition, not to every recorded measurement.
IF OBJECT_ID(N'dbo.metric_types', N'U') IS NULL
BEGIN
CREATE TABLE metric_types (
    id              INT IDENTITY(1,1)   PRIMARY KEY,
    code            NVARCHAR(50)        NOT NULL UNIQUE,
    unit            NVARCHAR(20)        NULL,
    description     NVARCHAR(255)       NULL
);
END;
GO

IF OBJECT_ID(N'dbo.telemetry_metrics', N'U') IS NULL
BEGIN
CREATE TABLE telemetry_metrics (
    id              BIGINT IDENTITY(1,1) PRIMARY KEY,   -- BIGINT cho time-series volume lớn
    node_id         INT                  NOT NULL,
    metric_type_id  INT                  NOT NULL,
    value           FLOAT                NOT NULL,
    timestamp       DATETIME2            NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_telemetry_node FOREIGN KEY (node_id)
        REFERENCES nodes(id) ON DELETE CASCADE,
    CONSTRAINT FK_telemetry_metric_type FOREIGN KEY (metric_type_id)
        REFERENCES metric_types(id)
);
END;
GO

IF OBJECT_ID(N'dbo.alert_thresholds', N'U') IS NULL
BEGIN
CREATE TABLE alert_thresholds (
    id                  INT IDENTITY(1,1) PRIMARY KEY,
    metric_type_id      INT               NOT NULL UNIQUE,
    warning_threshold   FLOAT             NOT NULL,
    critical_threshold  FLOAT             NOT NULL,
    duration_seconds    INT               NOT NULL DEFAULT 30,
    is_active           BIT               NOT NULL DEFAULT 1,
    created_by_user_id  INT               NULL,
    created_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_thresholds_user FOREIGN KEY (created_by_user_id)
        REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT FK_thresholds_metric_type FOREIGN KEY (metric_type_id)
        REFERENCES metric_types(id)
);
END;
GO

IF OBJECT_ID(N'dbo.alerts', N'U') IS NULL
BEGIN
CREATE TABLE alerts (
    id                      INT IDENTITY(1,1) PRIMARY KEY,
    node_id                 INT               NOT NULL,
    threshold_id            INT               NULL,
    alert_type              NVARCHAR(50)      NOT NULL,
    severity                NVARCHAR(20)      NOT NULL DEFAULT 'WARNING',
    status                  NVARCHAR(20)      NOT NULL DEFAULT 'OPEN',
    message                 NVARCHAR(MAX)     NOT NULL,
    metric_value            FLOAT             NOT NULL DEFAULT 0.0,
    triggered_at            DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    acknowledged_at         DATETIME2         NULL,
    resolved_at             DATETIME2         NULL,
    acknowledged_by_user_id INT               NULL,
    resolved_by_user_id     INT               NULL,

    CONSTRAINT FK_alerts_node FOREIGN KEY (node_id)
        REFERENCES nodes(id),

    CONSTRAINT FK_alerts_threshold FOREIGN KEY (threshold_id)
        REFERENCES alert_thresholds(id) ON DELETE SET NULL,

    CONSTRAINT FK_alerts_ack_user FOREIGN KEY (acknowledged_by_user_id)
        REFERENCES users(id),

    CONSTRAINT FK_alerts_resolve_user FOREIGN KEY (resolved_by_user_id)
        REFERENCES users(id),

    CONSTRAINT CK_alerts_severity CHECK (
        severity IN ('WARNING', 'CRITICAL')
    ),

    CONSTRAINT CK_alerts_status CHECK (
        status IN ('OPEN', 'ACKNOWLEDGED', 'RESOLVED', 'CLOSED')
    )
);
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_alerts_node_status' AND object_id = OBJECT_ID(N'dbo.alerts'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_alerts_node_status ON alerts(node_id, status);
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 5. NHÓM TICKET BẢO TRÌ SỰ CỐ (Incident & Maintenance Tickets)
-- ═══════════════════════════════════════════════════════════════════

IF OBJECT_ID(N'dbo.tickets', N'U') IS NULL
BEGIN
CREATE TABLE tickets (
    id                      INT IDENTITY(1,1) PRIMARY KEY,
    alert_id                INT               NULL,
    node_id                 INT               NOT NULL,
    title                   NVARCHAR(200)     NOT NULL,
    description             NVARCHAR(MAX)     NOT NULL,
    priority                NVARCHAR(20)      NOT NULL DEFAULT 'MEDIUM',
    status                  NVARCHAR(20)      NOT NULL DEFAULT 'OPEN',
    assigned_to_user_id     INT               NULL,
    created_by_user_id      INT               NULL,
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_tickets_alert FOREIGN KEY (alert_id)
        REFERENCES alerts(id) ON DELETE SET NULL,

    CONSTRAINT FK_tickets_node FOREIGN KEY (node_id)
        REFERENCES nodes(id),

    CONSTRAINT FK_tickets_assignee FOREIGN KEY (assigned_to_user_id)
        REFERENCES users(id),

    CONSTRAINT FK_tickets_creator FOREIGN KEY (created_by_user_id)
        REFERENCES users(id),

    CONSTRAINT CK_tickets_priority CHECK (
        priority IN ('LOW', 'MEDIUM', 'HIGH', 'URGENT', 'CRITICAL')
    ),

    CONSTRAINT CK_tickets_status CHECK (
        status IN ('OPEN', 'IN_PROGRESS', 'PENDING_CLOSURE', 'CLOSED')
    )
);
END;
GO

IF OBJECT_ID(N'dbo.ticket_notes', N'U') IS NULL
BEGIN
CREATE TABLE ticket_notes (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    ticket_id       INT               NOT NULL,
    author_user_id  INT               NOT NULL,
    note_text       NVARCHAR(MAX)     NOT NULL,
    created_at      DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_notes_ticket FOREIGN KEY (ticket_id)
        REFERENCES tickets(id) ON DELETE CASCADE,

    CONSTRAINT FK_notes_author FOREIGN KEY (author_user_id)
        REFERENCES users(id)
);
END;
GO

IF OBJECT_ID(N'dbo.ticket_closure_requests', N'U') IS NULL
BEGIN
CREATE TABLE ticket_closure_requests (
    id                      INT IDENTITY(1,1) PRIMARY KEY,
    ticket_id               INT               NOT NULL UNIQUE,
    requested_by_user_id    INT               NOT NULL,
    summary                 NVARCHAR(255)     NOT NULL,
    resolution_details      NVARCHAR(MAX)     NOT NULL,
    status                  NVARCHAR(20)      NOT NULL DEFAULT 'PENDING',
    reviewed_by_user_id     INT               NULL,
    reviewed_at             DATETIME2         NULL,
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_closure_ticket FOREIGN KEY (ticket_id)
        REFERENCES tickets(id) ON DELETE CASCADE,

    CONSTRAINT FK_closure_requester FOREIGN KEY (requested_by_user_id)
        REFERENCES users(id),

    CONSTRAINT FK_closure_reviewer FOREIGN KEY (reviewed_by_user_id)
        REFERENCES users(id),

    CONSTRAINT CK_closure_status CHECK (
        status IN ('PENDING', 'APPROVED', 'REJECTED')
    )
);
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 6. NHÓM QUẢN LÝ TÀI SẢN (Asset Lifecycle Management)
-- ═══════════════════════════════════════════════════════════════════

IF OBJECT_ID(N'dbo.warranty_info', N'U') IS NULL
BEGIN
CREATE TABLE warranty_info (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    node_id         INT               NOT NULL UNIQUE,
    vendor          NVARCHAR(100)     NOT NULL,
    model_number    NVARCHAR(100)     NOT NULL,
    serial_number   NVARCHAR(100)     NOT NULL,
    purchase_date   DATETIME2         NULL,
    warranty_start  DATETIME2         NULL,
    warranty_end    DATETIME2         NULL,
    support_contact NVARCHAR(255)     NULL,
    created_at      DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at      DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_warranty_node FOREIGN KEY (node_id)
        REFERENCES nodes(id) ON DELETE CASCADE
);
END;
GO

IF OBJECT_ID(N'dbo.asset_specs', N'U') IS NULL
BEGIN
CREATE TABLE asset_specs (
    id                      INT IDENTITY(1,1) PRIMARY KEY,
    node_id                 INT               NOT NULL UNIQUE,
    cpu_model               NVARCHAR(100)     NOT NULL,
    cpu_cores               INT               NOT NULL,
    total_ram_gb            FLOAT             NOT NULL,
    total_storage_gb        FLOAT             NOT NULL,
    os_name                 NVARCHAR(100)     NOT NULL,
    os_version              NVARCHAR(50)      NOT NULL,
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_specs_node FOREIGN KEY (node_id)
        REFERENCES nodes(id) ON DELETE CASCADE
);
END;
GO

-- Network interfaces are repeatable facts and therefore have one row per interface.
IF OBJECT_ID(N'dbo.asset_network_interfaces', N'U') IS NULL
BEGIN
CREATE TABLE asset_network_interfaces (
    asset_spec_id   INT                 NOT NULL,
    interface_name  NVARCHAR(100)       NOT NULL,
    mac_address     NVARCHAR(50)        NULL,
    ipv4_address    NVARCHAR(50)        NULL,
    ipv6_address    NVARCHAR(50)        NULL,
    speed_mbps      INT                 NULL,
    mtu             INT                 NULL,
    is_up           BIT                 NULL,

    CONSTRAINT PK_asset_network_interfaces PRIMARY KEY (asset_spec_id, interface_name),
    CONSTRAINT FK_asset_network_interfaces_spec FOREIGN KEY (asset_spec_id)
        REFERENCES asset_specs(id) ON DELETE CASCADE
);
END;
GO

IF OBJECT_ID(N'dbo.maintenance_histories', N'U') IS NULL
BEGIN
CREATE TABLE maintenance_histories (
    id                      INT IDENTITY(1,1) PRIMARY KEY,
    node_id                 INT               NOT NULL,
    ticket_id               INT               NULL,
    maintenance_type        NVARCHAR(50)      NOT NULL DEFAULT 'PREVENTIVE',
    description             NVARCHAR(MAX)     NOT NULL,
    performed_by_user_id    INT               NOT NULL,
    performed_at            DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    resolution_notes        NVARCHAR(MAX)     NULL,
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_maint_node FOREIGN KEY (node_id)
        REFERENCES nodes(id),

    CONSTRAINT FK_maint_ticket FOREIGN KEY (ticket_id)
        REFERENCES tickets(id) ON DELETE SET NULL,

    CONSTRAINT FK_maint_performer FOREIGN KEY (performed_by_user_id)
        REFERENCES users(id),

    CONSTRAINT CK_maint_type CHECK (
        maintenance_type IN ('PREVENTIVE', 'CORRECTIVE', 'EMERGENCY', 'INSPECTION')
    )
);
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 7. NHẬT KÝ KIỂM TOÁN BẤT BIẾN (Audit Log)
-- ═══════════════════════════════════════════════════════════════════

IF OBJECT_ID(N'dbo.audit_logs', N'U') IS NULL
BEGIN
CREATE TABLE audit_logs (
    id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_id         INT                  NULL,
    username        NVARCHAR(50)         NULL,
    action          NVARCHAR(100)        NOT NULL,
    target_entity   NVARCHAR(100)        NOT NULL,
    target_id       NVARCHAR(50)         NULL,
    details_json    NVARCHAR(MAX)        NULL,       -- JSON chi tiết thao tác
    ip_address      NVARCHAR(50)         NULL,
    timestamp       DATETIME2            NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_audit_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE SET NULL
);
END;
GO

-- Normalize legacy JSON/string fields transactionally before removing them.
BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(N'dbo.roles', N'permissions_json') IS NOT NULL
    BEGIN
        -- Expand each permission into the catalog and its role-permission relation.
        EXEC sys.sp_executesql N'
            IF EXISTS (
                SELECT 1
                FROM dbo.roles
                WHERE permissions_json IS NOT NULL
                  AND (ISJSON(permissions_json) <> 1
                       OR LEFT(LTRIM(permissions_json), 1) <> N''['')
            )
                THROW 51020, N''Invalid roles.permissions_json; normalize it manually before rerunning.'', 1;

            IF EXISTS (
                SELECT 1
                FROM dbo.roles role
                CROSS APPLY OPENJSON(role.permissions_json) item
                WHERE role.permissions_json IS NOT NULL AND item.[type] <> 1
            )
                THROW 51026, N''Role permissions must be a JSON string array.'', 1;

            INSERT INTO dbo.permissions (code)
            SELECT DISTINCT permission.value
            FROM dbo.roles role
            CROSS APPLY OPENJSON(role.permissions_json) permission
            WHERE NOT EXISTS (
                SELECT 1 FROM dbo.permissions p WHERE p.code = permission.value
            );

            INSERT INTO dbo.role_permissions (role_id, permission_id)
            SELECT role.id, permission.id
            FROM dbo.roles role
            CROSS APPLY OPENJSON(role.permissions_json) json_permission
            INNER JOIN dbo.permissions permission ON permission.code = json_permission.value
            WHERE NOT EXISTS (
                SELECT 1
                FROM dbo.role_permissions rp
                WHERE rp.role_id = role.id AND rp.permission_id = permission.id
            );

            ALTER TABLE dbo.roles DROP COLUMN permissions_json;';
    END;

    IF COL_LENGTH(N'dbo.markers', N'spatial_coordinates_json') IS NOT NULL
    BEGIN
        -- Refuse unknown axes so the upgrade cannot silently discard coordinates.
        EXEC sys.sp_executesql N'
            IF EXISTS (
                SELECT 1
                FROM dbo.markers
                WHERE spatial_coordinates_json IS NOT NULL
                  AND (ISJSON(spatial_coordinates_json) <> 1
                       OR LEFT(LTRIM(spatial_coordinates_json), 1) <> N''{'')
            )
                THROW 51021, N''Invalid markers.spatial_coordinates_json; normalize it manually before rerunning.'', 1;

            IF EXISTS (
                SELECT 1
                FROM dbo.markers marker
                CROSS APPLY OPENJSON(marker.spatial_coordinates_json) property
                WHERE marker.spatial_coordinates_json IS NOT NULL
                  AND property.[key] COLLATE DATABASE_DEFAULT NOT IN
                      (N''x'', N''y'', N''z'')
            )
                THROW 51022, N''Unexpected coordinate property; normalize it manually before rerunning.'', 1;

            INSERT INTO dbo.marker_coordinates (marker_id, x, y, z)
            SELECT marker.id, coordinate.x, coordinate.y, coordinate.z
            FROM dbo.markers marker
            CROSS APPLY OPENJSON(marker.spatial_coordinates_json)
                WITH (x FLOAT N''$.x'', y FLOAT N''$.y'', z FLOAT N''$.z'') coordinate
            WHERE marker.spatial_coordinates_json IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.marker_coordinates c WHERE c.marker_id = marker.id
              );

            ALTER TABLE dbo.markers DROP COLUMN spatial_coordinates_json;';
    END;

    IF COL_LENGTH(N'dbo.asset_specs', N'network_interfaces_json') IS NOT NULL
    BEGIN
        -- Convert known NIC attributes into typed columns; reject unknown JSON keys.
        EXEC sys.sp_executesql N'
            IF EXISTS (
                SELECT 1
                FROM dbo.asset_specs
                WHERE network_interfaces_json IS NOT NULL
                  AND (ISJSON(network_interfaces_json) <> 1
                       OR LEFT(LTRIM(network_interfaces_json), 1) <> N''['')
            )
                THROW 51023, N''Invalid asset_specs.network_interfaces_json; normalize it manually before rerunning.'', 1;

            IF EXISTS (
                SELECT 1
                FROM dbo.asset_specs spec
                CROSS APPLY OPENJSON(spec.network_interfaces_json) item
                WHERE spec.network_interfaces_json IS NOT NULL
                  AND (ISJSON(item.value) <> 1
                       OR LEFT(LTRIM(item.value), 1) <> N''{'')
            )
                THROW 51027, N''Each network interface must be a JSON object.'', 1;

            IF EXISTS (
                SELECT 1
                FROM dbo.asset_specs spec
                CROSS APPLY OPENJSON(spec.network_interfaces_json) item
                CROSS APPLY OPENJSON(item.value) property
                WHERE spec.network_interfaces_json IS NOT NULL
                  AND property.[key] COLLATE DATABASE_DEFAULT NOT IN
                      (N''name'', N''interface_name'', N''mac_address'', N''ipv4_address'',
                       N''ip_address'', N''ipv6_address'', N''speed_mbps'', N''mtu'', N''is_up'')
            )
                THROW 51024, N''Unexpected network-interface property; normalize it manually before rerunning.'', 1;

            INSERT INTO dbo.asset_network_interfaces
                (asset_spec_id, interface_name, mac_address, ipv4_address,
                 ipv6_address, speed_mbps, mtu, is_up)
            SELECT spec.id,
                   COALESCE(NULLIF(details.interface_name COLLATE DATABASE_DEFAULT, N''''),
                            NULLIF(details.name COLLATE DATABASE_DEFAULT, N''''),
                            CONCAT(N''interface-'', item.[key] COLLATE DATABASE_DEFAULT)),
                   details.mac_address,
                   COALESCE(details.ipv4_address, details.ip_address),
                   details.ipv6_address,
                   details.speed_mbps,
                   details.mtu,
                   details.is_up
            FROM dbo.asset_specs spec
            CROSS APPLY OPENJSON(spec.network_interfaces_json) item
            CROSS APPLY OPENJSON(item.value)
                WITH (interface_name NVARCHAR(100) N''$.interface_name'',
                      name NVARCHAR(100) N''$.name'',
                      mac_address NVARCHAR(50) N''$.mac_address'',
                      ipv4_address NVARCHAR(50) N''$.ipv4_address'',
                      ip_address NVARCHAR(50) N''$.ip_address'',
                      ipv6_address NVARCHAR(50) N''$.ipv6_address'',
                      speed_mbps INT N''$.speed_mbps'',
                      mtu INT N''$.mtu'',
                      is_up BIT N''$.is_up'') details
            WHERE spec.network_interfaces_json IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.asset_network_interfaces ni
                  WHERE ni.asset_spec_id = spec.id
                    AND ni.interface_name =
                        COALESCE(NULLIF(details.interface_name COLLATE DATABASE_DEFAULT, N''''),
                                 NULLIF(details.name COLLATE DATABASE_DEFAULT, N''''),
                                 CONCAT(N''interface-'', item.[key] COLLATE DATABASE_DEFAULT))
              );

            ALTER TABLE dbo.asset_specs DROP COLUMN network_interfaces_json;';
    END;

    IF COL_LENGTH(N'dbo.telemetry_metrics', N'metric_type') IS NOT NULL
    BEGIN
        -- Move metric labels and units into the shared metric dictionary.
        EXEC sys.sp_executesql N'
            IF EXISTS (
                SELECT metric_type
                FROM dbo.telemetry_metrics
                GROUP BY metric_type
                HAVING COUNT(DISTINCT unit) > 1
            )
                THROW 51025, N''A telemetry metric uses multiple units; reconcile units before rerunning.'', 1;

            INSERT INTO dbo.metric_types (code, unit)
            SELECT metric_type, MIN(unit)
            FROM dbo.telemetry_metrics legacy
            WHERE NOT EXISTS (
                SELECT 1 FROM dbo.metric_types mt WHERE mt.code = legacy.metric_type
            )
            GROUP BY metric_type;

            INSERT INTO dbo.metric_types (code)
            SELECT DISTINCT threshold.metric_type
            FROM dbo.alert_thresholds threshold
            WHERE NOT EXISTS (
                SELECT 1 FROM dbo.metric_types mt WHERE mt.code = threshold.metric_type
            );

            IF COL_LENGTH(N''dbo.telemetry_metrics'', N''metric_type_id'') IS NULL
                EXEC sys.sp_executesql N''ALTER TABLE dbo.telemetry_metrics ADD metric_type_id INT NULL;'';

            EXEC sys.sp_executesql N''
                UPDATE telemetry
                SET metric_type_id = metric.id
                FROM dbo.telemetry_metrics telemetry
                INNER JOIN dbo.metric_types metric ON metric.code = telemetry.metric_type;

                ALTER TABLE dbo.telemetry_metrics ALTER COLUMN metric_type_id INT NOT NULL;

                IF NOT EXISTS (
                    SELECT 1 FROM sys.foreign_keys
                    WHERE name = N''''FK_telemetry_metric_type''''
                      AND parent_object_id = OBJECT_ID(N''''dbo.telemetry_metrics'''')
                )
                    ALTER TABLE dbo.telemetry_metrics
                        ADD CONSTRAINT FK_telemetry_metric_type FOREIGN KEY (metric_type_id)
                        REFERENCES dbo.metric_types(id);

                IF EXISTS (
                    SELECT 1 FROM sys.indexes
                    WHERE name = N''''IX_telemetry_type_time''''
                      AND object_id = OBJECT_ID(N''''dbo.telemetry_metrics'''')
                )
                    DROP INDEX IX_telemetry_type_time ON dbo.telemetry_metrics;

                ALTER TABLE dbo.telemetry_metrics DROP COLUMN metric_type, unit;'';
            ';
    END;

    IF COL_LENGTH(N'dbo.alert_thresholds', N'metric_type') IS NOT NULL
    BEGIN
        EXEC sys.sp_executesql N'
            IF COL_LENGTH(N''dbo.alert_thresholds'', N''metric_type_id'') IS NULL
                EXEC sys.sp_executesql N''ALTER TABLE dbo.alert_thresholds ADD metric_type_id INT NULL;'';

            EXEC sys.sp_executesql N''
                UPDATE threshold
                SET metric_type_id = metric.id
                FROM dbo.alert_thresholds threshold
                INNER JOIN dbo.metric_types metric ON metric.code = threshold.metric_type;

                ALTER TABLE dbo.alert_thresholds ALTER COLUMN metric_type_id INT NOT NULL;

                IF NOT EXISTS (
                    SELECT 1 FROM sys.foreign_keys
                    WHERE name = N''''FK_thresholds_metric_type''''
                      AND parent_object_id = OBJECT_ID(N''''dbo.alert_thresholds'''')
                )
                    ALTER TABLE dbo.alert_thresholds
                        ADD CONSTRAINT FK_thresholds_metric_type FOREIGN KEY (metric_type_id)
                        REFERENCES dbo.metric_types(id);

                IF NOT EXISTS (SELECT 1 FROM sys.indexes
                               WHERE name = N''''UQ_alert_thresholds_metric_type_id''''
                                 AND object_id = OBJECT_ID(N''''dbo.alert_thresholds''''))
                    CREATE UNIQUE INDEX UQ_alert_thresholds_metric_type_id
                        ON dbo.alert_thresholds(metric_type_id);

                DECLARE @unique_constraint sysname;
                SELECT TOP (1) @unique_constraint = constraint_name.name
                FROM sys.key_constraints constraint_name
                INNER JOIN sys.index_columns index_column
                    ON index_column.object_id = constraint_name.parent_object_id
                   AND index_column.index_id = constraint_name.unique_index_id
                INNER JOIN sys.columns column_name
                    ON column_name.object_id = index_column.object_id
                   AND column_name.column_id = index_column.column_id
                WHERE constraint_name.parent_object_id = OBJECT_ID(N''''dbo.alert_thresholds'''')
                  AND constraint_name.type = N''''UQ''''
                  AND column_name.name = N''''metric_type'''';

                IF @unique_constraint IS NOT NULL
                BEGIN
                    DECLARE @drop_constraint_sql NVARCHAR(MAX);
                    SET @drop_constraint_sql =
                        N''''ALTER TABLE dbo.alert_thresholds DROP CONSTRAINT ''''
                        + QUOTENAME(@unique_constraint);
                    EXEC sys.sp_executesql @drop_constraint_sql;
                END;

                ALTER TABLE dbo.alert_thresholds DROP COLUMN metric_type;'';
            ';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- Time-series indexes are created after legacy columns have been migrated.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_node_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_telemetry_node_time ON telemetry_metrics(node_id, timestamp DESC);
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_metric_type_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_telemetry_metric_type_time ON telemetry_metrics(metric_type_id, timestamp DESC);
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_audit_timestamp' AND object_id = OBJECT_ID(N'dbo.audit_logs'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_audit_timestamp ON audit_logs(timestamp DESC);
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_audit_user' AND object_id = OBJECT_ID(N'dbo.audit_logs'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_audit_user ON audit_logs(user_id, timestamp DESC);
END;
GO

PRINT N'=== Tạo schema 25 bảng AR-IMMS thành công ===';
GO
