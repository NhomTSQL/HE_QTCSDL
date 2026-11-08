-- ============================================================================
-- AR-IMMS: Seed Data cho SQL Server
-- Dữ liệu mẫu khởi tạo: Roles, Users, Digital Twin hierarchy, Thresholds,
-- AR Markers, Telemetry, Alerts, Tickets
-- ============================================================================

USE AR_IMMS;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 1. VAI TRÒ RBAC
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM roles WHERE id = 1)
BEGIN
SET IDENTITY_INSERT roles ON;

INSERT INTO roles (id, name, description) VALUES
(1, N'ADMINISTRATOR',
    N'Quản trị viên toàn quyền hệ thống'),
(2, N'SYSTEM_OPERATOR',
    N'Vận hành viên trực ca Web Command Center'),
(3, N'FIELD_TECHNICIAN',
    N'Kỹ thuật viên hiện trường thao tác AR Mobile');

SET IDENTITY_INSERT roles OFF;
END;
GO

INSERT INTO permissions (code, description)
SELECT permission.code, permission.description
FROM (VALUES
    (N'all', N'Toàn quyền hệ thống'),
    (N'user:manage', N'Quản lý người dùng'),
    (N'site:manage', N'Quản lý địa điểm'),
    (N'threshold:manage', N'Quản lý ngưỡng cảnh báo'),
    (N'ticket:approve', N'Duyệt yêu cầu đóng ticket'),
    (N'telemetry:read', N'Xem dữ liệu telemetry'),
    (N'alert:ack', N'Xác nhận cảnh báo'),
    (N'ticket:create', N'Tạo ticket'),
    (N'ticket:assign', N'Phân công ticket'),
    (N'ar:scan', N'Quét mã tài sản'),
    (N'ticket:view_assigned', N'Xem ticket được giao'),
    (N'ticket:update', N'Cập nhật ticket'),
    (N'ticket:request_closure', N'Yêu cầu đóng ticket')
) permission(code, description)
WHERE NOT EXISTS (
    SELECT 1 FROM permissions existing WHERE existing.code = permission.code
);

INSERT INTO role_permissions (role_id, permission_id)
SELECT role_permission.role_id, permission.id
FROM (VALUES
    (1, N'all'), (1, N'user:manage'), (1, N'site:manage'),
    (1, N'threshold:manage'), (1, N'ticket:approve'),
    (2, N'telemetry:read'), (2, N'alert:ack'), (2, N'ticket:create'),
    (2, N'ticket:assign'), (2, N'ticket:approve'),
    (3, N'ar:scan'), (3, N'ticket:view_assigned'), (3, N'ticket:update'),
    (3, N'ticket:request_closure')
) role_permission(role_id, permission_code)
INNER JOIN roles role ON role.id = role_permission.role_id
INNER JOIN permissions permission ON permission.code = role_permission.permission_code
WHERE NOT EXISTS (
    SELECT 1
    FROM role_permissions existing
    WHERE existing.role_id = role_permission.role_id
      AND existing.permission_id = permission.id
);
GO

-- ═══════════════════════════════════════════════════════════════════
-- 2. NGƯỜI DÙNG MẪU
-- Password hash tạo bằng werkzeug.security.generate_password_hash
-- Password hashes below are placeholders; generate real hashes before deployment.
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM users WHERE id = 1)
BEGIN
SET IDENTITY_INSERT users ON;

INSERT INTO users (id, username, email, password_hash, full_name, role_id, is_active) VALUES
(1, N'admin',      N'admin@ar-imms.vn',    N'scrypt:32768:8:1$placeholder_admin_hash',      N'Nguyễn Văn Admin',      1, 1),
(2, N'operator',   N'operator@ar-imms.vn',  N'scrypt:32768:8:1$placeholder_operator_hash',   N'Nguyễn Văn Vận Hành',   2, 1),
(3, N'technician', N'tech@ar-imms.vn',      N'scrypt:32768:8:1$placeholder_tech_hash',        N'Lê Văn Technician',     3, 1);

SET IDENTITY_INSERT users OFF;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 3. CÂY PHÂN CẤP DIGITAL TWIN: Site → Room → Rack → Node
-- ═══════════════════════════════════════════════════════════════════

-- Site
IF NOT EXISTS (SELECT 1 FROM sites WHERE id = 1)
BEGIN
SET IDENTITY_INSERT sites ON;
INSERT INTO sites (id, name, code, location, description) VALUES
(1, N'Trung Tâm Dữ Liệu Hòa Lạc', N'DC-HN-01',
    N'Khu CNC Hòa Lạc, Hà Nội',
    N'Trung tâm dữ liệu chính DC-HN-01');
SET IDENTITY_INSERT sites OFF;
END;
GO

-- Room
IF NOT EXISTS (SELECT 1 FROM rooms WHERE id = 1)
BEGIN
SET IDENTITY_INSERT rooms ON;
INSERT INTO rooms (id, site_id, name, code, floor, description) VALUES
(1, 1, N'Phòng Máy Chủ A01', N'ROOM-A01', N'Tầng 2', N'Phòng máy chủ A01');
SET IDENTITY_INSERT rooms OFF;
END;
GO

-- Racks
IF NOT EXISTS (SELECT 1 FROM racks WHERE id = 1)
BEGIN
SET IDENTITY_INSERT racks ON;
INSERT INTO racks (id, room_id, name, code, unit_capacity, total_power_capacity_watts) VALUES
(1, 1, N'Tủ Rack Server A01', N'RACK-A01', 42, 10000.0),
(2, 1, N'Tủ Rack Server A02', N'RACK-A02', 42, 10000.0);
SET IDENTITY_INSERT racks OFF;
END;
GO

-- Nodes (4 máy tính đại diện 4 server trong mini testbed)
IF NOT EXISTS (SELECT 1 FROM nodes WHERE id = 1)
BEGIN
SET IDENTITY_INSERT nodes ON;
INSERT INTO nodes (id, rack_id, name, hostname, ip_address, mac_address,
                   rack_position_u, status, power_consumption_watts) VALUES
(1, 1, N'Server Alpha 01 - DB Master',      N'srv-alpha-01', N'192.168.10.11',
    N'00:1A:2B:3C:4D:01', 1, N'ONLINE',  280.0),
(2, 1, N'Server Beta 01 - AI Inference',     N'srv-beta-01',  N'192.168.10.12',
    N'00:1A:2B:3C:4D:02', 2, N'CRITICAL', 350.0),
(3, 2, N'Server Alpha 03 - API Gateway',     N'srv-alpha-03', N'192.168.10.13',
    N'00:1A:2B:3C:4D:03', 1, N'ONLINE',  240.0),
(4, 2, N'Server Delta 04 - Worker Node',     N'srv-delta-04', N'192.168.10.14',
    N'00:1A:2B:3C:4D:04', 2, N'ONLINE',  210.0);
SET IDENTITY_INSERT nodes OFF;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 4. AR MARKERS (QR Code & ArUco cho 4 Nodes)
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM markers WHERE marker_code = N'arimms://node/NODE-01')
BEGIN
INSERT INTO markers (node_id, marker_type, marker_code) VALUES
-- Node 1
(1, N'QR',    N'arimms://node/NODE-01'),
(1, N'QR',    N'NODE-01'),
(1, N'ARUCO', N'1'),
-- Node 2
(2, N'QR',    N'arimms://node/NODE-02'),
(2, N'QR',    N'NODE-02'),
(2, N'ARUCO', N'2'),
-- Node 3
(3, N'QR',    N'arimms://node/NODE-03'),
(3, N'QR',    N'NODE-03'),
(3, N'ARUCO', N'3'),
-- Node 4
(4, N'QR',    N'arimms://node/NODE-04'),
(4, N'QR',    N'NODE-04'),
(4, N'ARUCO', N'4');
END;
GO

INSERT INTO marker_coordinates (marker_id, x, y, z)
SELECT marker.id, 0.0, 0.1, -0.5
FROM markers marker
WHERE marker.marker_code IN
    (N'arimms://node/NODE-01', N'NODE-01', N'1',
     N'arimms://node/NODE-02', N'NODE-02', N'2',
     N'arimms://node/NODE-03', N'NODE-03', N'3',
     N'arimms://node/NODE-04', N'NODE-04', N'4')
  AND NOT EXISTS (
      SELECT 1 FROM marker_coordinates coordinates WHERE coordinates.marker_id = marker.id
  );
GO

-- ═══════════════════════════════════════════════════════════════════
-- 5. NGƯỠNG CẢNH BÁO (Alert Thresholds)
-- ═══════════════════════════════════════════════════════════════════

IF EXISTS (
    SELECT 1
    FROM (VALUES
        (N'cpu_usage_percent', N'%'),
        (N'memory_usage_percent', N'%'),
        (N'temperature_celsius', N'C'),
        (N'disk_usage_percent', N'%')
    ) expected(code, unit)
    INNER JOIN metric_types existing ON existing.code = expected.code
    WHERE existing.unit IS NOT NULL AND existing.unit <> expected.unit
)
    THROW 51028, N'Sample metric type has a conflicting canonical unit.', 1;

UPDATE existing
SET unit = expected.unit,
    description = expected.description
FROM metric_types existing
INNER JOIN (VALUES
    (N'cpu_usage_percent', N'%', N'Tỷ lệ sử dụng CPU'),
    (N'memory_usage_percent', N'%', N'Tỷ lệ sử dụng bộ nhớ'),
    (N'temperature_celsius', N'C', N'Nhiệt độ máy chủ'),
    (N'disk_usage_percent', N'%', N'Tỷ lệ sử dụng đĩa')
) expected(code, unit, description) ON expected.code = existing.code
WHERE existing.unit IS NULL OR existing.description IS NULL;

INSERT INTO metric_types (code, unit, description)
SELECT expected.code, expected.unit, expected.description
FROM (VALUES
    (N'cpu_usage_percent', N'%', N'Tỷ lệ sử dụng CPU'),
    (N'memory_usage_percent', N'%', N'Tỷ lệ sử dụng bộ nhớ'),
    (N'temperature_celsius', N'C', N'Nhiệt độ máy chủ'),
    (N'disk_usage_percent', N'%', N'Tỷ lệ sử dụng đĩa')
) expected(code, unit, description)
WHERE NOT EXISTS (
    SELECT 1 FROM metric_types existing WHERE existing.code = expected.code
);
GO

INSERT INTO alert_thresholds (metric_type_id, warning_threshold, critical_threshold, duration_seconds, is_active)
SELECT metric.id, threshold.warning_threshold, threshold.critical_threshold,
       threshold.duration_seconds, threshold.is_active
FROM (VALUES
    (N'cpu_usage_percent', 80.0, 90.0, 60, 1),
    (N'memory_usage_percent', 85.0, 92.0, 60, 1),
    (N'temperature_celsius', 65.0, 80.0, 30, 1),
    (N'disk_usage_percent', 85.0, 95.0, 120, 1)
) threshold(metric_code, warning_threshold, critical_threshold, duration_seconds, is_active)
INNER JOIN metric_types metric ON metric.code = threshold.metric_code
WHERE NOT EXISTS (
    SELECT 1 FROM alert_thresholds existing WHERE existing.metric_type_id = metric.id
);
GO

-- ═══════════════════════════════════════════════════════════════════
-- 6. TELEMETRY METRICS KHỞI TẠO (snapshot ban đầu cho 4 nodes)
-- ═══════════════════════════════════════════════════════════════════

DECLARE @now DATETIME2 = SYSUTCDATETIME();

IF NOT EXISTS (
    SELECT 1 FROM telemetry_metrics telemetry
    INNER JOIN metric_types metric ON metric.id = telemetry.metric_type_id
    WHERE telemetry.node_id = 1 AND metric.code = N'cpu_usage_percent' AND telemetry.value = 24.5
)
BEGIN
INSERT INTO telemetry_metrics (node_id, metric_type_id, value, timestamp)
SELECT sample.node_id, metric.id, sample.value, @now
FROM (VALUES
-- Node 1: Healthy
(1, N'cpu_usage_percent', 24.5),
(1, N'memory_usage_percent', 45.2),
(1, N'temperature_celsius', 52.0),
(1, N'disk_usage_percent', 61.0),
-- Node 2: Critical (CPU quá tải)
(2, N'cpu_usage_percent', 94.8),
(2, N'memory_usage_percent', 88.6),
(2, N'temperature_celsius', 81.5),
(2, N'disk_usage_percent', 68.0),
-- Node 3: Healthy
(3, N'cpu_usage_percent', 35.0),
(3, N'memory_usage_percent', 50.1),
(3, N'temperature_celsius', 55.0),
(3, N'disk_usage_percent', 58.0),
-- Node 4: Healthy
(4, N'cpu_usage_percent', 18.2),
(4, N'memory_usage_percent', 39.4),
(4, N'temperature_celsius', 49.0),
(4, N'disk_usage_percent', 45.0)
) sample(node_id, metric_code, value)
INNER JOIN metric_types metric ON metric.code = sample.metric_code;
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 7. ALERT MẪU (Node 2 CPU Critical)
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM alerts WHERE node_id = 2 AND alert_type = N'CPU_OVERLOAD')
BEGIN
INSERT INTO alerts (node_id, threshold_id, alert_type, severity, status, message, metric_value, triggered_at)
SELECT 2, threshold.id, N'CPU_OVERLOAD', N'CRITICAL', N'OPEN',
    N'Cảnh báo ĐỎ: CPU vượt ngưỡng giới hạn an toàn 94.8% (Ngưỡng Critical: 90%)',
    94.8, SYSUTCDATETIME()
FROM alert_thresholds threshold
INNER JOIN metric_types metric ON metric.id = threshold.metric_type_id
WHERE metric.code = N'cpu_usage_percent';
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 8. TICKET MẪU (Phân công Technician xử lý Node 2)
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM tickets WHERE title LIKE N'%srv-beta-01%')
BEGIN
INSERT INTO tickets (alert_id, node_id, title, description, priority, status,
                     assigned_to_user_id, created_by_user_id, created_at)
SELECT alert.id, 2,
    N'Khắc phục sự cố quá tải CPU srv-beta-01',
    N'Tiến trình stress test chiếm dụng toàn bộ tài nguyên CPU (>94%). Yêu cầu Kỹ thuật viên tới hiện trường sử dụng Mobile AR quét mã máy, thực hiện Step-up Verification tắt tiến trình rác và gửi Yêu cầu Nghiệm thu.',
    N'CRITICAL', N'IN_PROGRESS',
    3, 2,
    DATEADD(MINUTE, -15, SYSUTCDATETIME())
FROM alerts alert
WHERE alert.node_id = 2 AND alert.alert_type = N'CPU_OVERLOAD';
END;
GO

-- Ghi chú ticket
IF NOT EXISTS (
    SELECT 1
    FROM ticket_notes note
    INNER JOIN tickets ticket ON ticket.id = note.ticket_id
    WHERE ticket.title LIKE N'%srv-beta-01%' AND note.author_user_id = 2
)
BEGIN
INSERT INTO ticket_notes (ticket_id, author_user_id, note_text)
SELECT ticket.id, 2,
       N'Đã phát hiện cảnh báo CPU > 90% trên Web Command Center. Đã phân công cho Technician tiếp nhận xử lý.'
FROM tickets ticket
WHERE ticket.title LIKE N'%srv-beta-01%';
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 9. AUDIT LOG KHỞI TẠO
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM audit_logs WHERE action = N'SYSTEM_SEED' AND target_entity = N'DATABASE' AND target_id = N'AR_IMMS')
BEGIN
INSERT INTO audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address) VALUES
(1, N'admin', N'SYSTEM_SEED', N'DATABASE', N'AR_IMMS',
    N'{"event":"Khởi tạo dữ liệu mẫu hệ thống AR-IMMS","tables":25,"nodes":4}',
    N'127.0.0.1');
END;
GO

PRINT N'=== Nạp seed data AR-IMMS thành công ===';
GO
