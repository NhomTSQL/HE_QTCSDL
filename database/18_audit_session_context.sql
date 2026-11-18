-- 18_audit_session_context.sql
-- HQTCSDL-42: Flask truyen user hien tai vao SESSION_CONTEXT de audit ghi dung nguoi thao tac.
-- Chay lai nhieu lan an toan (CREATE OR ALTER). Chay SAU 04 (va 16, 17) vi ghi de trg_ticket_status_audit.
-- Test case: backend/test_audit_context.py (2 user khac nhau ack alert / doi trang thai ticket).

USE AR_IMMS;
GO

-- SP: dat thong tin nguoi thao tac vao SESSION_CONTEXT cua ket noi hien tai. Backend goi moi transaction.
-- Test case: EXEC usp_set_audit_context 1, N'admin', N'127.0.0.1'; SELECT SESSION_CONTEXT(N'username'); -> admin.
CREATE OR ALTER PROCEDURE usp_set_audit_context
    @user_id INT = NULL,
    @username NVARCHAR(50) = NULL,
    @ip_address NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sys.sp_set_session_context @key = N'user_id', @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'username', @value = @username;
    EXEC sys.sp_set_session_context @key = N'ip_address', @value = @ip_address;
END;
GO

-- Trigger: audit khi ticket doi trang thai. Nguoi thao tac lay tu SESSION_CONTEXT, khong co thi SYSTEM.
-- Test case: doi status ticket qua API bang user operator -> audit_logs.username = operator.
CREATE OR ALTER TRIGGER trg_ticket_status_audit ON tickets
AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ctx_user_id INT = CAST(SESSION_CONTEXT(N'user_id') AS INT);
    DECLARE @ctx_username NVARCHAR(50) = CAST(SESSION_CONTEXT(N'username') AS NVARCHAR(50));
    DECLARE @ctx_ip NVARCHAR(50) = CAST(SESSION_CONTEXT(N'ip_address') AS NVARCHAR(50));

    INSERT INTO audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
    SELECT @ctx_user_id,
           COALESCE(@ctx_username, N'SYSTEM'),
           N'TICKET_STATUS_CHANGED', N'TICKET',
           CAST(i.id AS NVARCHAR(50)),
           N'{"old_status":"' + d.status + N'","new_status":"' + i.status + N'"}',
           COALESCE(@ctx_ip, N'127.0.0.1'),
           SYSUTCDATETIME()
    FROM inserted i
    INNER JOIN deleted d ON i.id = d.id
    WHERE i.status <> d.status;
END;
GO

-- Trigger: audit khi alert duoc ack (OPEN -> ACKNOWLEDGED). Truoc day khong co audit cho thao tac nay.
-- Test case: ack alert qua API bang user admin -> audit_logs co ALERT_ACKNOWLEDGED, username = admin.
CREATE OR ALTER TRIGGER trg_alert_ack_audit ON alerts
AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ctx_user_id INT = CAST(SESSION_CONTEXT(N'user_id') AS INT);
    DECLARE @ctx_username NVARCHAR(50) = CAST(SESSION_CONTEXT(N'username') AS NVARCHAR(50));
    DECLARE @ctx_ip NVARCHAR(50) = CAST(SESSION_CONTEXT(N'ip_address') AS NVARCHAR(50));

    INSERT INTO audit_logs (user_id, username, action, target_entity, target_id, details_json, ip_address, timestamp)
    SELECT COALESCE(@ctx_user_id, i.acknowledged_by_user_id),
           COALESCE(@ctx_username,
                    (SELECT u.username FROM users u WHERE u.id = i.acknowledged_by_user_id),
                    N'SYSTEM'),
           N'ALERT_ACKNOWLEDGED', N'ALERT',
           CAST(i.id AS NVARCHAR(50)),
           N'{"old_status":"' + d.status + N'","new_status":"' + i.status + N'"}',
           COALESCE(@ctx_ip, N'127.0.0.1'),
           SYSUTCDATETIME()
    FROM inserted i
    INNER JOIN deleted d ON d.id = i.id
    WHERE i.status = N'ACKNOWLEDGED' AND d.status <> N'ACKNOWLEDGED';
END;
GO

PRINT N'=== HQTCSDL-42: audit SESSION_CONTEXT san sang ===';
GO