-- ============================================================================
-- AR-IMMS: Schema Tables cho SQL Server
-- Chuyển đổi từ SQLAlchemy/PostgreSQL → T-SQL
-- 20 bảng: roles, users, notifications, sites, rooms, racks, nodes,
--          containers, markers, data_collector_agents, telemetry_metrics,
--          alert_thresholds, alerts, tickets, ticket_notes,
--          ticket_closure_requests, warranty_info, asset_specs,
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
    permissions_json NVARCHAR(MAX)       NULL,       -- JSON lưu danh sách quyền
    description     NVARCHAR(255)       NULL
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
    spatial_coordinates_json NVARCHAR(MAX)    NULL,      -- JSON tọa độ không gian
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

IF OBJECT_ID(N'dbo.telemetry_metrics', N'U') IS NULL
BEGIN
CREATE TABLE telemetry_metrics (
    id              BIGINT IDENTITY(1,1) PRIMARY KEY,   -- BIGINT cho time-series volume lớn
    node_id         INT                  NOT NULL,
    metric_type     NVARCHAR(50)         NOT NULL,
    value           FLOAT                NOT NULL,
    unit            NVARCHAR(20)         NOT NULL,
    timestamp       DATETIME2            NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_telemetry_node FOREIGN KEY (node_id)
        REFERENCES nodes(id) ON DELETE CASCADE
);
END;
GO

-- Index tối ưu truy vấn time-series
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_node_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_telemetry_node_time ON telemetry_metrics(node_id, timestamp DESC);
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_telemetry_type_time' AND object_id = OBJECT_ID(N'dbo.telemetry_metrics'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_telemetry_type_time ON telemetry_metrics(metric_type, timestamp DESC);
END;
GO

IF OBJECT_ID(N'dbo.alert_thresholds', N'U') IS NULL
BEGIN
CREATE TABLE alert_thresholds (
    id                  INT IDENTITY(1,1) PRIMARY KEY,
    metric_type         NVARCHAR(50)      NOT NULL UNIQUE,
    warning_threshold   FLOAT             NOT NULL,
    critical_threshold  FLOAT             NOT NULL,
    duration_seconds    INT               NOT NULL DEFAULT 30,
    is_active           BIT               NOT NULL DEFAULT 1,
    created_by_user_id  INT               NULL,
    created_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at          DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_thresholds_user FOREIGN KEY (created_by_user_id)
        REFERENCES users(id) ON DELETE SET NULL
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
    network_interfaces_json NVARCHAR(MAX)     NULL,      -- JSON danh sách NIC
    created_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at              DATETIME2         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_specs_node FOREIGN KEY (node_id)
        REFERENCES nodes(id) ON DELETE CASCADE
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

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_audit_timestamp' AND object_id = OBJECT_ID(N'dbo.audit_logs'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_audit_timestamp ON audit_logs(timestamp DESC);
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_audit_user' AND object_id = OBJECT_ID(N'dbo.audit_logs'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_audit_user ON audit_logs(user_id, timestamp DESC);
END;
GO

PRINT N'=== Tạo schema 20 bảng AR-IMMS thành công ===';
GO
