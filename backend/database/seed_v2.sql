-- 1. SEED DỮ LIỆU USERS 
INSERT INTO users (id, username, password_hash, full_name, role, status, created_at) VALUES
('usr-001', 'admin', '$2b$10$ohNBWQsx2d83ISiejKZFNuN/aNxnM1CFdfjG1XjBKivPE7z.49Cnu', 'System Administrator', 'ADMIN', 'ACTIVE', GETDATE()),
('usr-002', 'operator', '$2b$10$AmGg9xo03M6Pcc32AzJTVeuPU8N9/J7rrZjwt74V79oX0bBaw2Bta', 'Data Center Operator', 'OPERATOR', 'ACTIVE', GETDATE()),
('usr-003', 'technician_levu', '$2b$10$oOs8g1nB6/WLZc0zaoHBjuNugNh/ZwNsY90jPinsjfGGZ7sLxRPUu', 'Lê Vũ (Field Tech)', 'TECHNICIAN', 'ACTIVE', GETDATE());

-- 2. SEED CẤP BẬC KHÔNG GIAN (SITE -> ROOM -> RACK)
INSERT INTO sites (id, name, code, location_description) VALUES
('site-001', 'HQTCSDL Lab Site', 'LAB-SITE-01', 'Phòng thí nghiệm HQTCSDL');

INSERT INTO rooms (id, site_id, name, code, floor) VALUES
('room-001', 'site-001', 'Server Room Mini', 'RM-402', 4);

INSERT INTO racks (id, room_id, name, code, total_u, status) VALUES
('rack-001', 'room-001', 'Mini DC Rack 01', 'RACK-01', 12, 'ACTIVE');

-- 3. SEED 3 MÁY THẬT TRONG TESTBED (NODES)
INSERT INTO nodes (id, rack_id, name, code, ip_address, mac_address, status, position_u, created_at) VALUES
('node-001', 'rack-001', 'Master Node (Laptop 1)', 'NODE-01', '192.168.1.101', 'AA:BB:CC:11:22:33', 'ONLINE', 1, GETDATE()),
('node-002', 'rack-001', 'Worker Node 01 (Laptop 2)', 'NODE-02', '192.168.1.102', 'AA:BB:CC:11:22:34', 'ONLINE', 3, GETDATE()),
('node-003', 'rack-001', 'Worker Node 02 (Laptop 3)', 'NODE-03', '192.168.1.103', 'AA:BB:CC:11:22:35', 'ONLINE', 5, GETDATE());

-- 4. SEED AR SPATIAL MARKERS (MÃ ARUCO/QR DÙNG CHO APP AR)
INSERT INTO ar_markers (id, node_id, marker_type, marker_value, description) VALUES
('mrk-001', 'node-001', 'ARUCO', 'ARUCO_ID_101', 'Marker gắn Laptop 1'),
('mrk-002', 'node-002', 'ARUCO', 'ARUCO_ID_102', 'Marker gắn Laptop 2'),
('mrk-003', 'node-003', 'ARUCO', 'ARUCO_ID_103', 'Marker gắn Laptop 3');

-- 5. SEED WORKLOADS / CONTAINERS DANG CHẠY TRÊN NODES
INSERT INTO workloads (id, node_id, name, container_id, image_name, status, port) VALUES
('wkl-001', 'node-001', 'nestjs-backend-api', 'cnt-c101a', 'node:18-alpine', 'RUNNING', 3000),
('wkl-002', 'node-001', 'sql-server-db', 'cnt-c101b', 'mcr.microsoft.com/mssql/server', 'RUNNING', 1433),
('wkl-003', 'node-002', 'telemetry-collector-agent', 'cnt-c102a', 'python:3.10-slim', 'RUNNING', 5000),
('wkl-004', 'node-003', 'nginx-reverse-proxy', 'cnt-c103a', 'nginx:alpine', 'RUNNING', 80); 