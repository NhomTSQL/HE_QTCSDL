-- Run after 01-05 have each been executed twice.
-- Expected: this script completes and prints the PASS message without throwing.
USE AR_IMMS;
GO

SET NOCOUNT ON;

IF (SELECT COUNT(*) FROM roles WHERE id IN (1, 2, 3)) <> 3
    THROW 51000, N'Expected the three sample roles.', 1;

IF (SELECT COUNT(*) FROM users WHERE id IN (1, 2, 3)) <> 3
    THROW 51001, N'Expected the three sample users.', 1;

IF (SELECT COUNT(*) FROM sites WHERE code = N'DC-HN-01') <> 1
    THROW 51002, N'Expected one sample site.', 1;

IF (SELECT COUNT(*) FROM rooms WHERE code = N'ROOM-A01') <> 1
    THROW 51003, N'Expected one sample room.', 1;

IF (SELECT COUNT(*) FROM racks WHERE code IN (N'RACK-A01', N'RACK-A02')) <> 2
    THROW 51004, N'Expected two sample racks.', 1;

IF (SELECT COUNT(*) FROM nodes WHERE hostname IN
    (N'srv-alpha-01', N'srv-beta-01', N'srv-alpha-03', N'srv-delta-04')) <> 4
    THROW 51005, N'Expected four sample nodes.', 1;

IF (SELECT COUNT(*) FROM markers WHERE marker_code IN
    (N'arimms://node/NODE-01', N'NODE-01', N'1',
     N'arimms://node/NODE-02', N'NODE-02', N'2',
     N'arimms://node/NODE-03', N'NODE-03', N'3',
     N'arimms://node/NODE-04', N'NODE-04', N'4')) <> 12
    THROW 51006, N'Expected twelve sample markers.', 1;

IF (SELECT COUNT(*)
    FROM alert_thresholds threshold
    INNER JOIN metric_types metric ON metric.id = threshold.metric_type_id
    WHERE metric.code IN
        (N'cpu_usage_percent', N'memory_usage_percent',
         N'temperature_celsius', N'disk_usage_percent')) <> 4
    THROW 51007, N'Expected four sample alert thresholds.', 1;

DECLARE @expected_telemetry TABLE (
    node_id INT,
    metric_type NVARCHAR(50),
    metric_value FLOAT
);

INSERT INTO @expected_telemetry (node_id, metric_type, metric_value)
VALUES
    (1, N'cpu_usage_percent', 24.5),
    (1, N'memory_usage_percent', 45.2),
    (1, N'temperature_celsius', 52.0),
    (1, N'disk_usage_percent', 61.0),
    (2, N'cpu_usage_percent', 94.8),
    (2, N'memory_usage_percent', 88.6),
    (2, N'temperature_celsius', 81.5),
    (2, N'disk_usage_percent', 68.0),
    (3, N'cpu_usage_percent', 35.0),
    (3, N'memory_usage_percent', 50.1),
    (3, N'temperature_celsius', 55.0),
    (3, N'disk_usage_percent', 58.0),
    (4, N'cpu_usage_percent', 18.2),
    (4, N'memory_usage_percent', 39.4),
    (4, N'temperature_celsius', 49.0),
    (4, N'disk_usage_percent', 45.0);

IF EXISTS (
    SELECT e.node_id, e.metric_type, e.metric_value
    FROM @expected_telemetry e
    LEFT JOIN telemetry_metrics telemetry
      ON telemetry.node_id = e.node_id
     AND telemetry.value = e.metric_value
    LEFT JOIN metric_types metric
      ON metric.id = telemetry.metric_type_id
     AND metric.code = e.metric_type
    GROUP BY e.node_id, e.metric_type, e.metric_value
    HAVING COUNT(metric.id) <> 1
)
    THROW 51008, N'Expected each sample telemetry row exactly once after rerunning the seed.', 1;

IF (SELECT COUNT(*) FROM alerts WHERE node_id = 2 AND alert_type = N'CPU_OVERLOAD') <> 1
    THROW 51009, N'Expected one sample CPU alert.', 1;

IF (SELECT COUNT(*) FROM tickets WHERE title LIKE N'%srv-beta-01%') <> 1
    THROW 51010, N'Expected one sample ticket.', 1;

IF (
    SELECT COUNT(*)
    FROM ticket_notes note
    INNER JOIN tickets ticket ON ticket.id = note.ticket_id
    WHERE ticket.title LIKE N'%srv-beta-01%' AND note.author_user_id = 2
) <> 1
    THROW 51011, N'Expected one sample ticket note.', 1;

IF (SELECT COUNT(*) FROM audit_logs WHERE action = N'SYSTEM_SEED'
    AND target_entity = N'DATABASE' AND target_id = N'AR_IMMS') <> 1
    THROW 51012, N'Expected one seed audit record.', 1;

IF OBJECT_ID(N'dbo.trg_users_updated_at', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.trg_nodes_updated_at', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.trg_tickets_updated_at', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.trg_alert_audit', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.trg_ticket_status_audit', N'TR') IS NULL
    THROW 51013, N'Expected all five triggers.', 1;

IF OBJECT_ID(N'dbo.sp_record_telemetry', N'P') IS NULL
   OR OBJECT_ID(N'dbo.sp_check_stale_nodes', N'P') IS NULL
   OR OBJECT_ID(N'dbo.sp_report_pue', N'P') IS NULL
   OR OBJECT_ID(N'dbo.sp_cleanup_old_telemetry', N'P') IS NULL
    THROW 51014, N'Expected all four stored procedures.', 1;

IF OBJECT_ID(N'dbo.vw_dashboard_summary', N'V') IS NULL
   OR OBJECT_ID(N'dbo.vw_latest_telemetry', N'V') IS NULL
   OR OBJECT_ID(N'dbo.vw_hierarchy_tree', N'V') IS NULL
    THROW 51015, N'Expected all three views.', 1;

IF OBJECT_ID(N'dbo.fn_average_mttr_minutes', N'FN') IS NULL
    THROW 51016, N'Expected the MTTR function.', 1;

IF (SELECT COUNT(*) FROM permissions) <> 13
   OR (SELECT COUNT(*) FROM role_permissions) <> 14
    THROW 51017, N'Expected normalized role-permission catalog and assignments.', 1;

IF (SELECT COUNT(*) FROM metric_types WHERE code IN
    (N'cpu_usage_percent', N'memory_usage_percent',
     N'temperature_celsius', N'disk_usage_percent')) <> 4
    THROW 51020, N'Expected four normalized metric types.', 1;

IF (SELECT COUNT(*) FROM marker_coordinates) <> 12
    THROW 51018, N'Expected one normalized coordinate row per sample marker.', 1;

IF OBJECT_ID(N'dbo.permissions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.role_permissions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.metric_types', N'U') IS NULL
   OR OBJECT_ID(N'dbo.marker_coordinates', N'U') IS NULL
   OR OBJECT_ID(N'dbo.asset_network_interfaces', N'U') IS NULL
    THROW 51021, N'Expected all normalized relation tables.', 1;

IF COL_LENGTH(N'dbo.roles', N'permissions_json') IS NOT NULL
   OR COL_LENGTH(N'dbo.markers', N'spatial_coordinates_json') IS NOT NULL
   OR COL_LENGTH(N'dbo.asset_specs', N'network_interfaces_json') IS NOT NULL
   OR COL_LENGTH(N'dbo.telemetry_metrics', N'metric_type') IS NOT NULL
   OR COL_LENGTH(N'dbo.telemetry_metrics', N'unit') IS NOT NULL
   OR COL_LENGTH(N'dbo.alert_thresholds', N'metric_type') IS NOT NULL
    THROW 51019, N'Legacy denormalized columns must not remain in the schema.', 1;

PRINT N'PASS: seed data and database objects are present exactly once after rerun.';
GO
