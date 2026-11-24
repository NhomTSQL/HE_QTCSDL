-- 17_dashboard_api_procedures.sql
-- Dashboard REST API procedures. Rerunnable; apply after scripts 01-04, 09, 16.
-- Backend accesses SQL Server only through these stored procedures.

USE AR_IMMS;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Test: seeded DB returns 4 nodes; node 1 CPU is 24.5. A node without samples
-- remains in the result with NULL metric values.
CREATE OR ALTER PROCEDURE dbo.usp_list_nodes_latest
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH latest AS (
        SELECT node_id,
               MAX(CASE WHEN metric_type = N'cpu_usage_percent' THEN value END) AS cpu_usage_percent,
               MAX(CASE WHEN metric_type = N'memory_usage_percent' THEN value END) AS memory_usage_percent,
               MAX(CASE WHEN metric_type = N'disk_usage_percent' THEN value END) AS disk_usage_percent,
               MAX(timestamp) AS collected_at
        FROM dbo.vw_latest_telemetry
        GROUP BY node_id
    )
    SELECT n.id, n.name, rk.name AS rack_name, r.name AS room_name, s.name AS site_name,
           n.status, n.last_ping_at, l.collected_at,
           l.cpu_usage_percent, l.memory_usage_percent, l.disk_usage_percent
    FROM dbo.nodes n
    JOIN dbo.racks rk ON rk.id = n.rack_id
    JOIN dbo.rooms r ON r.id = rk.room_id
    JOIN dbo.sites s ON s.id = r.site_id
    LEFT JOIN latest l ON l.node_id = n.id
    ORDER BY s.name, r.name, rk.name, n.name;
END;
GO

-- Test: OPEN,ACKNOWLEDGED returns only those states, newest first; empty filter returns all.
CREATE OR ALTER PROCEDURE dbo.usp_list_alerts
    @statuses NVARCHAR(200) = N'OPEN,ACKNOWLEDGED'
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.id, a.node_id, n.name AS node_name, a.alert_type, a.severity, a.status,
           a.message, a.metric_value, a.triggered_at, a.acknowledged_at
    FROM dbo.alerts a
    JOIN dbo.nodes n ON n.id = a.node_id
    WHERE NULLIF(LTRIM(RTRIM(@statuses)), N'') IS NULL
       OR EXISTS (SELECT 1 FROM STRING_SPLIT(@statuses, N',') st WHERE LTRIM(RTRIM(st.value)) = a.status)
    ORDER BY a.triggered_at DESC, a.id DESC;
END;
GO

-- Test: OPEN -> ACKNOWLEDGED records user/time; unknown id throws 51060;
-- repeating acknowledgement throws 51061.
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
    UPDATE dbo.alerts
    SET status = N'ACKNOWLEDGED', acknowledged_at = SYSUTCDATETIME(), acknowledged_by_user_id = @user_id
    WHERE id = @alert_id;
    SELECT id, status, acknowledged_at FROM dbo.alerts WHERE id = @alert_id;
END;
GO

-- Test: NULL/empty statuses returns all; OPEN returns only open tickets.
CREATE OR ALTER PROCEDURE dbo.usp_list_tickets
    @statuses NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.id, t.alert_id, t.node_id, n.name AS node_name, t.title, t.description,
           t.priority, t.status, t.assigned_to_user_id, au.username AS assigned_to_username,
           t.created_by_user_id, cu.username AS created_by_username, t.created_at, t.updated_at
    FROM dbo.tickets t
    JOIN dbo.nodes n ON n.id = t.node_id
    LEFT JOIN dbo.users au ON au.id = t.assigned_to_user_id
    LEFT JOIN dbo.users cu ON cu.id = t.created_by_user_id
    WHERE NULLIF(LTRIM(RTRIM(@statuses)), N'') IS NULL
       OR EXISTS (SELECT 1 FROM STRING_SPLIT(@statuses, N',') st WHERE LTRIM(RTRIM(st.value)) = t.status)
    ORDER BY t.created_at DESC, t.id DESC;
END;
GO

-- Test: valid node/priority returns new ticket id; unknown node throws 51062;
-- invalid priority throws 51063; invalid alert throws 51064.
CREATE OR ALTER PROCEDURE dbo.usp_create_ticket
    @node_id INT,
    @title NVARCHAR(200),
    @description NVARCHAR(MAX),
    @priority NVARCHAR(20) = N'MEDIUM',
    @created_by_user_id INT,
    @alert_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51062, N'Node not found.', 1;
    IF @priority NOT IN (N'LOW', N'MEDIUM', N'HIGH', N'URGENT', N'CRITICAL')
        THROW 51063, N'Invalid priority.', 1;
    IF @alert_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.alerts WHERE id = @alert_id)
        THROW 51064, N'Alert not found.', 1;
    INSERT dbo.tickets(alert_id, node_id, title, description, priority, status, created_by_user_id)
    VALUES (@alert_id, @node_id, @title, @description, @priority, N'OPEN', @created_by_user_id);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS id;
END;
GO

-- Test: OPEN -> IN_PROGRESS succeeds; OPEN -> CLOSED throws 51066;
-- missing ticket throws 51065; invalid state throws 51067.
CREATE OR ALTER PROCEDURE dbo.usp_update_ticket_status
    @ticket_id INT,
    @new_status NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @current NVARCHAR(20);
    SELECT @current = status FROM dbo.tickets WHERE id = @ticket_id;
    IF @current IS NULL THROW 51065, N'Ticket not found.', 1;
    IF @new_status NOT IN (N'OPEN', N'IN_PROGRESS', N'PENDING_CLOSURE', N'CLOSED')
        THROW 51067, N'Invalid ticket status.', 1;
    IF NOT ((@current = N'OPEN' AND @new_status = N'IN_PROGRESS')
         OR (@current = N'IN_PROGRESS' AND @new_status = N'PENDING_CLOSURE')
         OR (@current = N'PENDING_CLOSURE' AND @new_status = N'CLOSED'))
        THROW 51066, N'Invalid ticket status transition.', 1;
    UPDATE dbo.tickets SET status = @new_status WHERE id = @ticket_id;
    SELECT id, status, updated_at FROM dbo.tickets WHERE id = @ticket_id;
END;
GO
PRINT N'Dashboard API procedures ready.';
GO
