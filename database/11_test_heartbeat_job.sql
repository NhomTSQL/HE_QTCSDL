-- 11_test_heartbeat_job.sql
-- HQTCSDL-31: kiem thu SQL Agent Job AR_IMMS_Check_Stale_Nodes. Chay lai nhieu lan an toan.
-- Kich ban: node test mat heartbeat > 90 giay.
-- Mong doi: job (15 giay/lan) chuyen node sang UNAVAILABLE, co dung 1 alert NODE_UNAVAILABLE
--           dang mo, va chay them nhieu chu ky van khong tao alert trung.
-- Thoi gian chay: khoang 1 - 1,5 phut. Can SQL Server Agent dang chay va job da duoc tao (script 10).
-- Moi lan chay xoa alert cu cua node TEST (chi node srv-test-heartbeat) de test luon kiem tra that.

USE AR_IMMS;
GO
SET NOCOUNT ON;

DECLARE @hostname NVARCHAR(100) = N'srv-test-heartbeat';
DECLARE @node_id INT = (SELECT id FROM nodes WHERE hostname = @hostname);

-- Tao node test rieng (khong dung node seed) neu chua co
IF @node_id IS NULL
BEGIN
    INSERT INTO nodes (rack_id, name, hostname, ip_address, status, last_ping_at)
    VALUES ((SELECT MIN(id) FROM racks), N'TEST heartbeat node', @hostname,
            N'192.168.10.250', N'ONLINE', SYSUTCDATETIME());
    SET @node_id = (SELECT id FROM nodes WHERE hostname = @hostname);
END;

-- Don alert cu cua node test de moi lan chay deu bat dau tu trang thai sach
DELETE FROM alerts WHERE node_id = @node_id AND alert_type = N'NODE_UNAVAILABLE';

-- Buoc 1: node vua gui heartbeat
UPDATE nodes SET status = N'ONLINE', last_ping_at = SYSUTCDATETIME() WHERE id = @node_id;
PRINT N'Node test id = ' + CAST(@node_id AS NVARCHAR(10)) + N' dang ONLINE, chua co alert.';

-- Buoc 2: gia lap agent tat qua 90 giay (heartbeat cuoi cach day 120 giay)
UPDATE nodes SET last_ping_at = DATEADD(SECOND, -120, SYSUTCDATETIME()) WHERE id = @node_id;
PRINT N'Da gia lap mat heartbeat 120 giay. Dang cho SQL Agent Job chay (toi da 45 giay)...';

DECLARE @waited INT = 0;
DECLARE @status NVARCHAR(20) = (SELECT status FROM nodes WHERE id = @node_id);
WHILE @waited < 45 AND @status <> N'UNAVAILABLE'
BEGIN
    WAITFOR DELAY '00:00:03';
    SET @waited += 3;
    SET @status = (SELECT status FROM nodes WHERE id = @node_id);
END;

IF @status <> N'UNAVAILABLE'
    THROW 51060, N'FAIL: job khong chuyen node sang UNAVAILABLE trong 45 giay. Kiem tra SQL Agent va job.', 1;
PRINT N'PASS: job chuyen node sang UNAVAILABLE sau khoang ' + CAST(@waited AS NVARCHAR(10)) + N' giay.';

DECLARE @open_after INT = (
    SELECT COUNT(*) FROM alerts
    WHERE node_id = @node_id AND alert_type = N'NODE_UNAVAILABLE'
      AND status IN (N'OPEN', N'ACKNOWLEDGED'));
IF @open_after <> 1
    THROW 51061, N'FAIL: khong co dung 1 alert NODE_UNAVAILABLE dang mo cho node test.', 1;
PRINT N'PASS: co dung 1 alert NODE_UNAVAILABLE dang mo.';

-- Buoc 3: cho them 2 chu ky job, khong duoc tao alert trung
WAITFOR DELAY '00:00:35';
DECLARE @open_later INT = (
    SELECT COUNT(*) FROM alerts
    WHERE node_id = @node_id AND alert_type = N'NODE_UNAVAILABLE'
      AND status IN (N'OPEN', N'ACKNOWLEDGED'));
IF @open_later <> 1
    THROW 51062, N'FAIL: job chay lai nhung tao alert trung.', 1;
PRINT N'PASS: job chay them nhieu chu ky van chi co 1 alert (chong trung).';

-- Don dep: dua node test sang MAINTENANCE de khong lam nhieu he thong (SP bo qua node nay)
UPDATE nodes SET status = N'MAINTENANCE' WHERE id = @node_id;
GO