-- 19_test_alert_ticket.sql
-- HQTCSDL-34: test case SQL cho alert va ticket (kich ban + ket qua mong doi).
-- Kiem thu stored procedure trong 17_dashboard_api_procedures.sql. Chay lai nhieu lan an toan:
-- dau script xoa du lieu test cu, tao node test rieng (MAINTENANCE nen SQL Agent job bo qua),
-- cuoi script don sach. Yeu cau: da chay 01-04, 16, 17. Moi PASS/FAIL in ra; FAIL dung script (sqlcmd -b).
--
-- KICH BAN                                                        KET QUA MONG DOI
-- A1  ack alert OPEN boi operator                                 status ACKNOWLEDGED, co thoi gian + nguoi ack
-- A2  ack lai alert da ack                                        loi 51061
-- A3  ack alert khong ton tai                                     loi 51060
-- A4  ack alert RESOLVED                                          loi 51061
-- L1  usp_list_alerts 'OPEN'                                      co alert OPEN, khong co ACK / RESOLVED
-- L2  usp_list_alerts 'ACKNOWLEDGED'                              chi co alert da ack
-- L3  usp_list_alerts 'OPEN,ACKNOWLEDGED'                         co OPEN + ACK, khong co RESOLVED
-- L4  usp_list_alerts NULL                                        co ca 3 alert test
-- T1  tao ticket hop le (priority LOW)                            tra id, status OPEN, dung nguoi tao
-- T2  tao ticket gan alert, bo qua priority                       priority MEDIUM, alert_id dung
-- T3  node khong ton tai                                          loi 51062
-- T4  priority khong hop le                                       loi 51063
-- T5  alert khong ton tai                                         loi 51064
-- S1  OPEN -> IN_PROGRESS -> PENDING_CLOSURE -> CLOSED            tung buoc thanh cong
-- S2  OPEN -> CLOSED (nhay coc)                                   loi 51066
-- S3  ticket khong ton tai                                        loi 51065
-- S4  trang thai khong hop le ('FOO')                             loi 51067
-- S5  CLOSED -> OPEN (di nguoc)                                   loi 51066
-- S6  audit_logs                                                  3 dong TICKET_STATUS_CHANGED cua ticket, ghi old/new status
-- LT1 usp_list_tickets NULL / 'OPEN' / 'CLOSED'                   loc dung, created_by_username = operator

USE AR_IMMS;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'tempdb..#t34_expect_error') IS NOT NULL DROP PROCEDURE #t34_expect_error;
IF OBJECT_ID(N'tempdb..#t34_load_list') IS NOT NULL DROP PROCEDURE #t34_load_list;
GO

-- Chay @sql, mong doi dung loi so @expected.
CREATE PROCEDURE #t34_expect_error
    @sql NVARCHAR(MAX), @expected INT, @label NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @m NVARCHAR(2048);
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = @expected
        BEGIN
            PRINT N'PASS ' + @label + N' (loi ' + CAST(@expected AS NVARCHAR(20)) + N')';
            RETURN;
        END;
        SET @m = N'FAIL ' + @label + N': loi ' + CAST(ERROR_NUMBER() AS NVARCHAR(20))
                 + N' thay vi ' + CAST(@expected AS NVARCHAR(20)) + N' - ' + ERROR_MESSAGE();
        THROW 51099, @m, 1;
    END CATCH;
    SET @m = N'FAIL ' + @label + N': khong co loi (mong doi ' + CAST(@expected AS NVARCHAR(20)) + N')';
    THROW 51098, @m, 1;
END;
GO

-- Chay thu tuc danh sach (@cmd), nap ket qua vao bang tam toan cuc ##t34_list de dem/loc.
CREATE PROCEDURE #t34_load_list
    @cmd NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID(N'tempdb..##t34_list') IS NOT NULL DROP TABLE ##t34_list;
    DECLARE @cols NVARCHAR(MAX) = (
        SELECT STRING_AGG(CAST(QUOTENAME(name) + N' ' + system_type_name + N' NULL' AS NVARCHAR(MAX)), N', ')
               WITHIN GROUP (ORDER BY column_ordinal)
        FROM sys.dm_exec_describe_first_result_set(@cmd, NULL, 0));
    IF @cols IS NULL
        THROW 51097, N'FAIL: khong mo ta duoc cot ket qua cua thu tuc danh sach.', 1;
    DECLARE @sql NVARCHAR(MAX) = N'CREATE TABLE ##t34_list (' + @cols + N'); INSERT ##t34_list ' + @cmd + N';';
    EXEC sys.sp_executesql @sql;
END;
GO

-- ==================== DU LIEU TEST ====================
DECLARE @operator_id INT = (SELECT id FROM users WHERE username = N'operator');
DECLARE @admin_id INT = (SELECT id FROM users WHERE username = N'admin');
IF @operator_id IS NULL OR @admin_id IS NULL
    THROW 51080, N'FAIL: thieu user seed admin/operator (chay 03_seed_data.sql).', 1;

DECLARE @node_id INT = (SELECT id FROM nodes WHERE hostname = N'srv-test-alert-ticket');
IF @node_id IS NOT NULL
BEGIN
    DELETE FROM tickets WHERE node_id = @node_id;
    DELETE FROM alerts WHERE node_id = @node_id;
    DELETE FROM nodes WHERE id = @node_id;
END;
INSERT INTO nodes (rack_id, name, hostname, ip_address, status, last_ping_at)
VALUES ((SELECT MIN(id) FROM racks), N'TEST34 node', N'srv-test-alert-ticket',
        N'192.168.10.251', N'MAINTENANCE', SYSUTCDATETIME());
SET @node_id = (SELECT id FROM nodes WHERE hostname = N'srv-test-alert-ticket');

INSERT INTO alerts (node_id, alert_type, severity, status, message, metric_value) VALUES
    (@node_id, N'TEST34_A', N'CRITICAL', N'OPEN',     N'test34 alert A', 0.0),
    (@node_id, N'TEST34_B', N'CRITICAL', N'OPEN',     N'test34 alert B', 0.0),
    (@node_id, N'TEST34_C', N'WARNING',  N'RESOLVED', N'test34 alert C', 0.0);
DECLARE @alert_a INT = (SELECT id FROM alerts WHERE node_id = @node_id AND alert_type = N'TEST34_A');
DECLARE @alert_b INT = (SELECT id FROM alerts WHERE node_id = @node_id AND alert_type = N'TEST34_B');
DECLARE @alert_c INT = (SELECT id FROM alerts WHERE node_id = @node_id AND alert_type = N'TEST34_C');

DECLARE @sql NVARCHAR(MAX);

-- ==================== ALERT ====================
-- A1
DECLARE @ack TABLE (id INT, status NVARCHAR(20), acknowledged_at DATETIME2);
INSERT @ack EXEC dbo.usp_acknowledge_alert @alert_id = @alert_a, @user_id = @operator_id;
IF (SELECT COUNT(*) FROM @ack WHERE id = @alert_a AND status = N'ACKNOWLEDGED' AND acknowledged_at IS NOT NULL) <> 1
    THROW 51090, N'FAIL A1: ack khong tra ve ACKNOWLEDGED.', 1;
IF NOT EXISTS (SELECT 1 FROM alerts WHERE id = @alert_a AND status = N'ACKNOWLEDGED'
               AND acknowledged_by_user_id = @operator_id AND acknowledged_at IS NOT NULL)
    THROW 51091, N'FAIL A1: bang alerts khong ghi dung nguoi/thoi gian ack.', 1;
PRINT N'PASS A1 ack alert OPEN: ACKNOWLEDGED, ghi dung nguoi + thoi gian';

-- A2
SET @sql = N'EXEC AR_IMMS.dbo.usp_acknowledge_alert @alert_id = ' + CAST(@alert_a AS NVARCHAR(20))
         + N', @user_id = ' + CAST(@operator_id AS NVARCHAR(20));
EXEC #t34_expect_error @sql, 51061, N'A2 ack lai alert da ack';

-- A3
SET @sql = N'EXEC AR_IMMS.dbo.usp_acknowledge_alert @alert_id = -1, @user_id = ' + CAST(@operator_id AS NVARCHAR(20));
EXEC #t34_expect_error @sql, 51060, N'A3 ack alert khong ton tai';

-- A4
SET @sql = N'EXEC AR_IMMS.dbo.usp_acknowledge_alert @alert_id = ' + CAST(@alert_c AS NVARCHAR(20))
         + N', @user_id = ' + CAST(@operator_id AS NVARCHAR(20));
EXEC #t34_expect_error @sql, 51061, N'A4 ack alert RESOLVED';

-- L1: A da ACK, B OPEN, C RESOLVED
EXEC #t34_load_list @cmd = N'EXEC AR_IMMS.dbo.usp_list_alerts @statuses = N''OPEN''';
IF (SELECT COUNT(*) FROM ##t34_list WHERE id = @alert_b) <> 1
   OR (SELECT COUNT(*) FROM ##t34_list WHERE id IN (@alert_a, @alert_c)) <> 0
    THROW 51092, N'FAIL L1: loc OPEN phai co B, khong co A (ACK) va C (RESOLVED).', 1;
PRINT N'PASS L1 usp_list_alerts OPEN';

-- L2
EXEC #t34_load_list @cmd = N'EXEC AR_IMMS.dbo.usp_list_alerts @statuses = N''ACKNOWLEDGED''';
IF (SELECT COUNT(*) FROM ##t34_list WHERE id = @alert_a) <> 1
   OR (SELECT COUNT(*) FROM ##t34_list WHERE id IN (@alert_b, @alert_c)) <> 0
    THROW 51093, N'FAIL L2: loc ACKNOWLEDGED chi duoc co A.', 1;
PRINT N'PASS L2 usp_list_alerts ACKNOWLEDGED';

-- L3
EXEC #t34_load_list @cmd = N'EXEC AR_IMMS.dbo.usp_list_alerts @statuses = N''OPEN,ACKNOWLEDGED''';
IF (SELECT COUNT(*) FROM ##t34_list WHERE id IN (@alert_a, @alert_b)) <> 2
   OR (SELECT COUNT(*) FROM ##t34_list WHERE id = @alert_c) <> 0
    THROW 51094, N'FAIL L3: loc OPEN,ACKNOWLEDGED phai co A, B va khong co C.', 1;
PRINT N'PASS L3 usp_list_alerts OPEN,ACKNOWLEDGED';

-- L4
EXEC #t34_load_list @cmd = N'EXEC AR_IMMS.dbo.usp_list_alerts @statuses = NULL';
IF (SELECT COUNT(*) FROM ##t34_list WHERE id IN (@alert_a, @alert_b, @alert_c)) <> 3
    THROW 51095, N'FAIL L4: NULL phai tra ve ca 3 alert test.', 1;
PRINT N'PASS L4 usp_list_alerts NULL tra ve tat ca';

-- ==================== TICKET ====================
-- T1
DECLARE @new_ticket TABLE (id INT);
INSERT @new_ticket EXEC dbo.usp_create_ticket
    @node_id = @node_id, @title = N'TEST34 ticket 1', @description = N'kich ban test 1',
    @priority = N'LOW', @created_by_user_id = @operator_id;
DECLARE @ticket1 INT = (SELECT MAX(id) FROM @new_ticket);
IF @ticket1 IS NULL OR NOT EXISTS (SELECT 1 FROM tickets WHERE id = @ticket1 AND node_id = @node_id
    AND status = N'OPEN' AND priority = N'LOW' AND created_by_user_id = @operator_id AND alert_id IS NULL)
    THROW 51100, N'FAIL T1: tao ticket hop le khong dung (id/status/priority/nguoi tao).', 1;
PRINT N'PASS T1 tao ticket hop le: OPEN, LOW, dung nguoi tao';

-- T2
DELETE FROM @new_ticket;
INSERT @new_ticket EXEC dbo.usp_create_ticket
    @node_id = @node_id, @title = N'TEST34 ticket 2', @description = N'kich ban test 2',
    @created_by_user_id = @admin_id, @alert_id = @alert_b;
DECLARE @ticket2 INT = (SELECT MAX(id) FROM @new_ticket);
IF @ticket2 IS NULL OR NOT EXISTS (SELECT 1 FROM tickets WHERE id = @ticket2
    AND priority = N'MEDIUM' AND alert_id = @alert_b AND status = N'OPEN')
    THROW 51101, N'FAIL T2: priority mac dinh phai la MEDIUM va alert_id phai dung.', 1;
PRINT N'PASS T2 tao ticket gan alert: priority MEDIUM mac dinh, alert_id dung';

-- T3
SET @sql = N'EXEC AR_IMMS.dbo.usp_create_ticket @node_id = -1, @title = N''TEST34 x'', @description = N''x'', '
         + N'@priority = N''LOW'', @created_by_user_id = ' + CAST(@operator_id AS NVARCHAR(20));
EXEC #t34_expect_error @sql, 51062, N'T3 node khong ton tai';

-- T4
SET @sql = N'EXEC AR_IMMS.dbo.usp_create_ticket @node_id = ' + CAST(@node_id AS NVARCHAR(20))
         + N', @title = N''TEST34 x'', @description = N''x'', @priority = N''BAD'', @created_by_user_id = '
         + CAST(@operator_id AS NVARCHAR(20));
EXEC #t34_expect_error @sql, 51063, N'T4 priority khong hop le';

-- T5
SET @sql = N'EXEC AR_IMMS.dbo.usp_create_ticket @node_id = ' + CAST(@node_id AS NVARCHAR(20))
         + N', @title = N''TEST34 x'', @description = N''x'', @priority = N''LOW'', @created_by_user_id = '
         + CAST(@operator_id AS NVARCHAR(20)) + N', @alert_id = -1';
EXEC #t34_expect_error @sql, 51064, N'T5 alert khong ton tai';

-- S1: ticket1 di het vong doi
DECLARE @st TABLE (id INT, status NVARCHAR(20), updated_at DATETIME2);
INSERT @st EXEC dbo.usp_update_ticket_status @ticket_id = @ticket1, @new_status = N'IN_PROGRESS';
IF (SELECT status FROM tickets WHERE id = @ticket1) <> N'IN_PROGRESS'
    THROW 51102, N'FAIL S1: OPEN -> IN_PROGRESS that bai.', 1;
INSERT @st EXEC dbo.usp_update_ticket_status @ticket_id = @ticket1, @new_status = N'PENDING_CLOSURE';
IF (SELECT status FROM tickets WHERE id = @ticket1) <> N'PENDING_CLOSURE'
    THROW 51103, N'FAIL S1: IN_PROGRESS -> PENDING_CLOSURE that bai.', 1;
INSERT @st EXEC dbo.usp_update_ticket_status @ticket_id = @ticket1, @new_status = N'CLOSED';
IF (SELECT status FROM tickets WHERE id = @ticket1) <> N'CLOSED'
    THROW 51104, N'FAIL S1: PENDING_CLOSURE -> CLOSED that bai.', 1;
PRINT N'PASS S1 OPEN -> IN_PROGRESS -> PENDING_CLOSURE -> CLOSED';

-- S2 (ticket2 dang OPEN)
SET @sql = N'EXEC AR_IMMS.dbo.usp_update_ticket_status @ticket_id = ' + CAST(@ticket2 AS NVARCHAR(20))
         + N', @new_status = N''CLOSED''';
EXEC #t34_expect_error @sql, 51066, N'S2 OPEN -> CLOSED (nhay coc)';

-- S3
EXEC #t34_expect_error N'EXEC AR_IMMS.dbo.usp_update_ticket_status @ticket_id = -1, @new_status = N''OPEN''',
     51065, N'S3 ticket khong ton tai';

-- S4
SET @sql = N'EXEC AR_IMMS.dbo.usp_update_ticket_status @ticket_id = ' + CAST(@ticket2 AS NVARCHAR(20))
         + N', @new_status = N''FOO''';
EXEC #t34_expect_error @sql, 51067, N'S4 trang thai khong hop le';

-- S5 (ticket1 dang CLOSED)
SET @sql = N'EXEC AR_IMMS.dbo.usp_update_ticket_status @ticket_id = ' + CAST(@ticket1 AS NVARCHAR(20))
         + N', @new_status = N''OPEN''';
EXEC #t34_expect_error @sql, 51066, N'S5 CLOSED -> OPEN (di nguoc)';

-- S6: audit
IF (SELECT COUNT(*) FROM audit_logs WHERE action = N'TICKET_STATUS_CHANGED'
    AND target_id = CAST(@ticket1 AS NVARCHAR(50))) <> 3
    THROW 51105, N'FAIL S6: ticket1 phai co dung 3 dong audit TICKET_STATUS_CHANGED.', 1;
IF NOT EXISTS (SELECT 1 FROM audit_logs WHERE action = N'TICKET_STATUS_CHANGED'
    AND target_id = CAST(@ticket1 AS NVARCHAR(50))
    AND details_json LIKE N'%"old_status":"OPEN","new_status":"IN_PROGRESS"%')
    THROW 51106, N'FAIL S6: audit khong ghi dung old_status/new_status.', 1;
PRINT N'PASS S6 audit_logs ghi 3 lan doi trang thai voi old/new status';

-- LT1: loc ticket (ticket1 CLOSED, ticket2 OPEN)
EXEC #t34_load_list @cmd = N'EXEC AR_IMMS.dbo.usp_list_tickets @statuses = NULL';
IF (SELECT COUNT(*) FROM ##t34_list WHERE id IN (@ticket1, @ticket2)) <> 2
    THROW 51107, N'FAIL LT1: NULL phai tra ve ca 2 ticket test.', 1;
IF (SELECT created_by_username FROM ##t34_list WHERE id = @ticket1) <> N'operator'
    THROW 51108, N'FAIL LT1: created_by_username phai la operator.', 1;
EXEC #t34_load_list @cmd = N'EXEC AR_IMMS.dbo.usp_list_tickets @statuses = N''OPEN''';
IF (SELECT COUNT(*) FROM ##t34_list WHERE id = @ticket2) <> 1
   OR (SELECT COUNT(*) FROM ##t34_list WHERE id = @ticket1) <> 0
    THROW 51109, N'FAIL LT1: loc OPEN phai co ticket2, khong co ticket1.', 1;
EXEC #t34_load_list @cmd = N'EXEC AR_IMMS.dbo.usp_list_tickets @statuses = N''CLOSED''';
IF (SELECT COUNT(*) FROM ##t34_list WHERE id = @ticket1) <> 1
   OR (SELECT COUNT(*) FROM ##t34_list WHERE id = @ticket2) <> 0
    THROW 51110, N'FAIL LT1: loc CLOSED phai co ticket1, khong co ticket2.', 1;
PRINT N'PASS LT1 usp_list_tickets loc dung theo trang thai, join dung nguoi tao';

-- ==================== DON DEP ====================
IF OBJECT_ID(N'tempdb..##t34_list') IS NOT NULL DROP TABLE ##t34_list;
DELETE FROM tickets WHERE node_id = @node_id;
DELETE FROM alerts WHERE node_id = @node_id;
DELETE FROM nodes WHERE id = @node_id;
PRINT N'=== HQTCSDL-34: 19 kich ban alert/ticket deu PASS, da don du lieu test ===';
GO