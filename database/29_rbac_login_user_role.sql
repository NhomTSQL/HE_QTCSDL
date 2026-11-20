-- ============================================================================
-- HQTCSDL-40: SQL Login/User/Role, GRANT/DENY cho 3 vai + test từng vai
--
-- 3 vai (khớp roles trong 03_seed_data.sql và _READ_ROLES/_OPERATOR_ROLES
-- trong backend/dashboard_api.py):
--   ADMINISTRATOR     -> db_ar_imms_admin       (user ar_imms_admin)
--   SYSTEM_OPERATOR   -> db_ar_imms_operator    (user ar_imms_operator)
--   FIELD_TECHNICIAN  -> db_ar_imms_technician  (user ar_imms_technician)
--
-- Mô hình 4 lớp:
--   LOGIN (cấp server, "chìa khóa vào SQL Server")
--     -> USER (cấp database, "tư cách trong AR_IMMS")
--       -> ROLE (nhóm quyền, user chỉ là thành viên của role)
--         -> GRANT/DENY (quyền thật sự, gán cho ROLE chứ không gán cho từng user)
--
-- Nguyên tắc phân quyền:
--   1. Cả 3 vai bị DENY SELECT/INSERT/UPDATE/DELETE trực tiếp trên schema dbo
--      -> chỉ làm việc qua Stored Procedure (đúng ràng buộc của đồ án).
--      Stored Procedure vẫn chạy được nhờ ownership chaining (SP và bảng cùng
--      chủ dbo, SP không dùng dynamic SQL).
--   2. Mỗi SP thuộc 1 nhóm: R (cả 3 vai), O (Operator + Admin), A (chỉ Admin).
--      Technician: GRANT nhóm R, DENY nhóm O và A.
--      Operator  : GRANT nhóm R và O, DENY nhóm A.
--      Admin     : GRANT cả R, O, A.
--   3. DENY luôn thắng GRANT. Ghi DENY rõ ràng (thay vì chỉ "không GRANT")
--      để minh chứng được quyền bị chặn và không bị lỡ cấp qua role khác.
--   4. Quyền theo từng dòng dữ liệu (technician chỉ sửa ticket được giao) do
--      SP usp_authorize_ticket_write / usp_authorize_container_restart xử lý,
--      script này chỉ lo quyền cấp đối tượng.
--
-- Cách chạy:
--   * SSMS: bật Query > SQLCMD Mode rồi Execute.
--   * Mặc định (không điền mật khẩu): tạo USER WITHOUT LOGIN để test bằng
--     EXECUTE AS, không tạo Login thật.
--   * Muốn tạo Login thật: sửa 3 dòng :setvar bên dưới (KHÔNG commit mật khẩu
--     thật lên Git), mật khẩu phải đạt chính sách Windows (CHECK_POLICY = ON).
-- ============================================================================

USE AR_IMMS;
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

:setvar AR_IMMS_ADMIN_PASSWORD ""
:setvar AR_IMMS_OPERATOR_PASSWORD ""
:setvar AR_IMMS_TECHNICIAN_PASSWORD ""
GO

-- ═══════════════════════════════════════════════════════════════════
-- 1. LOGIN (server) + USER (database).
-- ═══════════════════════════════════════════════════════════════════
DECLARE @principal TABLE (name sysname PRIMARY KEY, password_plain NVARCHAR(256) NOT NULL);
INSERT INTO @principal (name, password_plain) VALUES
    (N'ar_imms_admin',      N'$(AR_IMMS_ADMIN_PASSWORD)'),
    (N'ar_imms_operator',   N'$(AR_IMMS_OPERATOR_PASSWORD)'),
    (N'ar_imms_technician', N'$(AR_IMMS_TECHNICIAN_PASSWORD)');

DECLARE @name sysname, @pwd NVARCHAR(256), @sql NVARCHAR(MAX);

DECLARE principal_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name, password_plain FROM @principal;
OPEN principal_cursor;
FETCH NEXT FROM principal_cursor INTO @name, @pwd;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF NULLIF(LTRIM(RTRIM(@pwd)), N'') IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @name)
        BEGIN
            SET @sql = N'CREATE LOGIN ' + QUOTENAME(@name)
                     + N' WITH PASSWORD = N''' + REPLACE(@pwd, N'''', N'''''')
                     + N''', CHECK_POLICY = ON, DEFAULT_DATABASE = [AR_IMMS];';
            EXEC sys.sp_executesql @sql;
            PRINT N'Đã tạo LOGIN ' + @name;
        END;

        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @name)
        BEGIN
            SET @sql = N'CREATE USER ' + QUOTENAME(@name) + N' FOR LOGIN ' + QUOTENAME(@name) + N';';
            EXEC sys.sp_executesql @sql;
            PRINT N'Đã tạo USER ' + @name + N' (gắn với LOGIN cùng tên)';
        END
        ELSE IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @name AND authentication_type = 0)
        BEGIN
            -- Lần chạy trước tạo WITHOUT LOGIN, lần này có mật khẩu: nối user với login.
            SET @sql = N'ALTER USER ' + QUOTENAME(@name) + N' WITH LOGIN = ' + QUOTENAME(@name) + N';';
            EXEC sys.sp_executesql @sql;
            PRINT N'Đã nối USER ' + @name + N' với LOGIN cùng tên';
        END;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @name)
    BEGIN
        SET @sql = N'CREATE USER ' + QUOTENAME(@name) + N' WITHOUT LOGIN;';
        EXEC sys.sp_executesql @sql;
        PRINT N'Đã tạo USER ' + @name + N' WITHOUT LOGIN (chế độ kiểm thử)';
    END;

    FETCH NEXT FROM principal_cursor INTO @name, @pwd;
END;

CLOSE principal_cursor;
DEALLOCATE principal_cursor;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 2. DATABASE ROLE + thành viên
-- Mỗi user chỉ thuộc đúng 1 role của mình; nếu lỡ thuộc role khác thì gỡ ra
-- ═══════════════════════════════════════════════════════════════════
DECLARE @role_map TABLE (role_name sysname PRIMARY KEY, user_name sysname NOT NULL);
INSERT INTO @role_map (role_name, user_name) VALUES
    (N'db_ar_imms_admin',      N'ar_imms_admin'),
    (N'db_ar_imms_operator',   N'ar_imms_operator'),
    (N'db_ar_imms_technician', N'ar_imms_technician');

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'CREATE ROLE ' + QUOTENAME(m.role_name) + N';' + CHAR(10)
FROM @role_map m
WHERE NOT EXISTS (
    SELECT 1 FROM sys.database_principals p WHERE p.name = m.role_name AND p.type = 'R'
);

SELECT @sql += N'ALTER ROLE ' + QUOTENAME(r.name) + N' DROP MEMBER ' + QUOTENAME(u.name) + N';' + CHAR(10)
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals u ON u.principal_id = rm.member_principal_id
WHERE r.name IN (SELECT role_name FROM @role_map)
  AND u.name IN (SELECT user_name FROM @role_map)
  AND NOT EXISTS (SELECT 1 FROM @role_map m WHERE m.role_name = r.name AND m.user_name = u.name);

IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;

SET @sql = N'';
SELECT @sql += N'ALTER ROLE ' + QUOTENAME(m.role_name) + N' ADD MEMBER ' + QUOTENAME(m.user_name) + N';' + CHAR(10)
FROM @role_map m
WHERE NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members rm
    JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
    JOIN sys.database_principals u ON u.principal_id = rm.member_principal_id
    WHERE r.name = m.role_name AND u.name = m.user_name
);
IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 3. MA TRẬN QUYỀN: mỗi stored procedure thuộc nhóm R / O / A
--    R = mọi vai (xem dữ liệu, thao tác ticket được giao, ghi chú, bàn giao ca)
--    O = Operator + Admin (đăng ký node, xác nhận cảnh báo, tạo/giao ticket...)
--    A = chỉ Admin (quản lý người dùng, duyệt yêu cầu tài khoản, xem audit)
-- Nguồn: decorator require_roles của từng endpoint trong dashboard_api.py.
-- ═══════════════════════════════════════════════════════════════════
IF OBJECT_ID(N'tempdb..#proc_scope') IS NOT NULL DROP TABLE #proc_scope;
CREATE TABLE #proc_scope (
    proc_name sysname NOT NULL PRIMARY KEY,
    scope     CHAR(1) NOT NULL CHECK (scope IN ('R', 'O', 'A'))
);

INSERT INTO #proc_scope (proc_name, scope) VALUES
    -- Nhóm R: cả 3 vai
    (N'usp_set_audit_context',              'R').
    (N'usp_get_analytics_summary',          'R'),
    (N'usp_get_capacity_report',            'R'),
    (N'usp_get_telemetry_history',          'R'),
    (N'usp_get_hierarchical_report',        'R'),
    (N'usp_list_racks',                     'R'),
    (N'usp_list_nodes_latest',              'R'),
    (N'usp_list_sites_and_rooms',           'R'),
    (N'usp_list_containers',                'R'),
    (N'usp_authorize_container_restart',    'R'),
    (N'usp_restart_container',              'R'),
    (N'usp_lookup_node_by_marker',          'R'),
    (N'usp_list_alerts',                    'R'),
    (N'usp_list_alert_thresholds',          'R'),
    (N'usp_list_tickets',                   'R'),
    (N'usp_authorize_ticket_write',         'R'),
    (N'usp_update_ticket_status',           'R'),
    (N'usp_list_ticket_notes',              'R'),
    (N'usp_add_ticket_note',                'R'),
    (N'usp_submit_ticket_closure_request',  'R'),
    (N'usp_list_assets',                    'R'),
    (N'usp_list_maintenance_histories',     'R'),
    (N'usp_list_handover_notes',            'R'),
    (N'usp_add_handover_note',              'R'),
    (N'usp_list_notifications',             'R'),
    (N'usp_mark_notification_read',         'R'),
    (N'usp_list_collector_agents',          'R'),
    -- Nhóm O: Operator + Admin
    (N'usp_register_node',                  'O'),
    (N'usp_update_node',                    'O'),
    (N'usp_manage_hierarchy',               'O'),
    (N'usp_manage_marker',                  'O'),
    (N'usp_acknowledge_alert',              'O'),
    (N'usp_update_alert_status',            'O'),
    (N'usp_update_alert_threshold',         'O'),
    (N'usp_create_ticket',                  'O'),
    (N'usp_assign_ticket',                  'O'),
    (N'usp_review_ticket_closure_request',  'O'),
    (N'usp_upsert_asset_warranty',          'O'),
    (N'usp_list_assignable_technicians',    'O'),
    (N'usp_manage_collector_agent',         'O'),
    -- Nhóm A: chỉ Admin
    (N'usp_list_users',                     'A'),
    (N'usp_manage_user',                    'A'),
    (N'usp_list_account_access_requests',   'A'),
    (N'usp_review_account_access_request',  'A'),
    (N'usp_list_audit_logs',                'A');

-- SP chưa tồn tạithì cảnh báo và bỏ qua, không vỡ script.
DECLARE @missing NVARCHAR(MAX) = N'';
SELECT @missing += proc_name + N' '
FROM #proc_scope
WHERE OBJECT_ID(N'dbo.' + proc_name, N'P') IS NULL;

IF LEN(@missing) > 0
    PRINT N'CẢNH BÁO: chưa có SP, bỏ qua: ' + @missing + N'-> kiểm tra đã chạy đủ script 01..26 chưa.';

DELETE FROM #proc_scope WHERE OBJECT_ID(N'dbo.' + proc_name, N'P') IS NULL;
GO

-- ═══════════════════════════════════════════════════════════════════
-- 4. ÁP DỤNG GRANT / DENY
-- Bước 4a: REVOKE sạch quyền cũ của 3 role để lần chạy lại phản ánh đúng ma trận mới.
-- Bước 4b: GRANT/DENY EXECUTE từng SP theo nhóm.
-- Bước 4c: DENY thao tác bảng trực tiếp.
-- ═══════════════════════════════════════════════════════════════════
DECLARE @sql NVARCHAR(MAX) = N'';

-- 4a
SELECT @sql += N'REVOKE ' + p.permission_name + N' ON '
    + CASE p.class
        WHEN 1 THEN N'OBJECT::' + QUOTENAME(OBJECT_SCHEMA_NAME(p.major_id)) + N'.' + QUOTENAME(OBJECT_NAME(p.major_id))
        ELSE N'SCHEMA::' + QUOTENAME(SCHEMA_NAME(p.major_id))
      END
    + N' FROM ' + QUOTENAME(r.name) + N';' + CHAR(10)
FROM sys.database_permissions p
JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
WHERE r.name IN (N'db_ar_imms_admin', N'db_ar_imms_operator', N'db_ar_imms_technician')
  AND p.class IN (1, 3)      -- 1 = object, 3 = schema (không đụng CONNECT ở cấp database)
  AND p.minor_id = 0;
IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;

-- 4b: role_rank 3/2/1; scope R/O/A cần rank 1/2/3 -> được GRANT khi rank >= yêu cầu
SET @sql = N'';
SELECT @sql += CASE WHEN x.is_allowed = 1 THEN N'GRANT' ELSE N'DENY' END
    + N' EXECUTE ON OBJECT::dbo.' + QUOTENAME(s.proc_name)
    + N' TO ' + QUOTENAME(r.role_name) + N';' + CHAR(10)
FROM #proc_scope s
CROSS JOIN (VALUES (N'db_ar_imms_admin', 3),
                   (N'db_ar_imms_operator', 2),
                   (N'db_ar_imms_technician', 1)) r(role_name, role_rank)
CROSS APPLY (
    SELECT CASE WHEN r.role_rank >= CASE s.scope WHEN 'R' THEN 1 WHEN 'O' THEN 2 ELSE 3 END
                THEN 1 ELSE 0 END AS is_allowed
) x;
EXEC sys.sp_executesql @sql;

-- 4c: cấm đọc/ghi bảng trực tiếp (kể cả Admin) -> mọi thao tác phải qua SP.
-- audit_logs còn có thêm trigger trg_audit_logs_immutable chặn UPDATE/DELETE.
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO db_ar_imms_admin;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO db_ar_imms_operator;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO db_ar_imms_technician;

PRINT N'Đã áp dụng GRANT/DENY cho 3 role.';
GO

