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

INSERT INTO roles (id, name, description, permissions_json) VALUES
(1, N'ADMINISTRATOR',
    N'Quản trị viên toàn quyền hệ thống',
    N'["all","user:manage","site:manage","threshold:manage","ticket:approve"]'),
(2, N'SYSTEM_OPERATOR',
    N'Vận hành viên trực ca Web Command Center',
    N'["telemetry:read","alert:ack","ticket:create","ticket:assign","ticket:approve"]'),
(3, N'FIELD_TECHNICIAN',
    N'Kỹ thuật viên hiện trường thao tác AR Mobile',
    N'["ar:scan","ticket:view_assigned","ticket:update","ticket:request_closure"]');

SET IDENTITY_INSERT roles OFF;
END;
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
INSERT INTO markers (node_id, marker_type, marker_code, spatial_coordinates_json) VALUES
-- Node 1
(1, N'QR',    N'arimms://node/NODE-01', N'{"x":0.0,"y":0.1,"z":-0.5}'),
(1, N'QR',    N'NODE-01',               N'{"x":0.0,"y":0.1,"z":-0.5}'),
(1, N'ARUCO', N'1',                     N'{"x":0.0,"y":0.1,"z":-0.5}'),
-- Node 2
(2, N'QR',    N'arimms://node/NODE-02', N'{"x":0.0,"y":0.1,"z":-0.5}'),
(2, N'QR',    N'NODE-02',               N'{"x":0.0,"y":0.1,"z":-0.5}'),
(2, N'ARUCO', N'2',                     N'{"x":0.0,"y":0.1,"z":-0.5}'),
-- Node 3
(3, N'QR',    N'arimms://node/NODE-03', N'{"x":0.0,"y":0.1,"z":-0.5}'),
(3, N'QR',    N'NODE-03',               N'{"x":0.0,"y":0.1,"z":-0.5}'),
(3, N'ARUCO', N'3',                     N'{"x":0.0,"y":0.1,"z":-0.5}'),
-- Node 4
(4, N'QR',    N'arimms://node/NODE-04', N'{"x":0.0,"y":0.1,"z":-0.5}'),
(4, N'QR',    N'NODE-04',               N'{"x":0.0,"y":0.1,"z":-0.5}'),
(4, N'ARUCO', N'4',                     N'{"x":0.0,"y":0.1,"z":-0.5}');
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 5. NGƯỠNG CẢNH BÁO (Alert Thresholds)
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM alert_thresholds WHERE metric_type = N'cpu_usage_percent')
BEGIN
INSERT INTO alert_thresholds (metric_type, warning_threshold, critical_threshold, duration_seconds, is_active) VALUES
(N'cpu_usage_percent',      80.0, 90.0,  60, 1),
(N'memory_usage_percent',   85.0, 92.0,  60, 1),
(N'temperature_celsius',    65.0, 80.0,  30, 1),
(N'disk_usage_percent',     85.0, 95.0, 120, 1);
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 6. TELEMETRY METRICS KHỞI TẠO (snapshot ban đầu cho 4 nodes)
-- ═══════════════════════════════════════════════════════════════════

DECLARE @now DATETIME2 = SYSUTCDATETIME();

IF NOT EXISTS (SELECT 1 FROM telemetry_metrics WHERE node_id = 1 AND metric_type = N'cpu_usage_percent' AND value = 24.5 AND unit = N'%')
BEGIN
INSERT INTO telemetry_metrics (node_id, metric_type, value, unit, timestamp) VALUES
-- Node 1: Healthy
(1, N'cpu_usage_percent',    24.5, N'%', @now),
(1, N'memory_usage_percent', 45.2, N'%', @now),
(1, N'temperature_celsius',  52.0, N'C', @now),
(1, N'disk_usage_percent',   61.0, N'%', @now),
-- Node 2: Critical (CPU quá tải)
(2, N'cpu_usage_percent',    94.8, N'%', @now),
(2, N'memory_usage_percent', 88.6, N'%', @now),
(2, N'temperature_celsius',  81.5, N'C', @now),
(2, N'disk_usage_percent',   68.0, N'%', @now),
-- Node 3: Healthy
(3, N'cpu_usage_percent',    35.0, N'%', @now),
(3, N'memory_usage_percent', 50.1, N'%', @now),
(3, N'temperature_celsius',  55.0, N'C', @now),
(3, N'disk_usage_percent',   58.0, N'%', @now),
-- Node 4: Healthy
(4, N'cpu_usage_percent',    18.2, N'%', @now),
(4, N'memory_usage_percent', 39.4, N'%', @now),
(4, N'temperature_celsius',  49.0, N'C', @now),
(4, N'disk_usage_percent',   45.0, N'%', @now);
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 7. ALERT MẪU (Node 2 CPU Critical)
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM alerts WHERE node_id = 2 AND alert_type = N'CPU_OVERLOAD')
BEGIN
INSERT INTO alerts (node_id, threshold_id, alert_type, severity, status, message, metric_value, triggered_at) VALUES
(2, 1, N'CPU_OVERLOAD', N'CRITICAL', N'OPEN',
    N'Cảnh báo ĐỎ: CPU vượt ngưỡng giới hạn an toàn 94.8% (Ngưỡng Critical: 90%)',
    94.8, SYSUTCDATETIME());
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 8. TICKET MẪU (Phân công Technician xử lý Node 2)
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM tickets WHERE title LIKE N'%srv-beta-01%')
BEGIN
INSERT INTO tickets (alert_id, node_id, title, description, priority, status,
                     assigned_to_user_id, created_by_user_id, created_at) VALUES
(1, 2,
    N'Khắc phục sự cố quá tải CPU srv-beta-01',
    N'Tiến trình stress test chiếm dụng toàn bộ tài nguyên CPU (>94%). Yêu cầu Kỹ thuật viên tới hiện trường sử dụng Mobile AR quét mã máy, thực hiện Step-up Verification tắt tiến trình rác và gửi Yêu cầu Nghiệm thu.',
    N'CRITICAL', N'IN_PROGRESS',
    3, 2,
    DATEADD(MINUTE, -15, SYSUTCDATETIME()));
END;
GO

-- Ghi chú ticket
IF NOT EXISTS (SELECT 1 FROM ticket_notes WHERE ticket_id = 1 AND author_user_id = 2)
BEGIN
INSERT INTO ticket_notes (ticket_id, author_user_id, note_text) VALUES
(1, 2,
    N'Đã phát hiện cảnh báo CPU > 90% trên Web Command Center. Đã phân công cho Technician tiếp nhận xử lý.');
END;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 9. AUDIT LOG KHỞI TẠO
-- ═══════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM audit_logs WHERE action = N'SYSTEM_SEED' AND target_entity = N'DATABASE' AND target_id = N'AR_IMMS')
BEGIN
INSERT INTO audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address) VALUES
(1, N'admin', N'SYSTEM_SEED', N'DATABASE', N'AR_IMMS',
    N'{"event":"Khởi tạo dữ liệu mẫu hệ thống AR-IMMS","tables":20,"nodes":4}',
    N'127.0.0.1');
END;
GO

PRINT N'=== Nạp seed data AR-IMMS thành công ===';
GO
