-- 23_test_warranty_status.sql
-- HQTCSDL-57: test view/SP bao hanh. Chay lai nhieu lan an toan: tao 4 node test rieng
-- (MAINTENANCE nen SQL Agent job bo qua) voi 4 tinh huong bao hanh, don du lieu cu o dau,
-- don sach o cuoi. Yeu cau: da chay 01-04 va 22.
--
-- KICH BAN                                    KET QUA MONG DOI
-- T1  node het han 10 ngay truoc              warranty_status = EXPIRED, days_remaining = -10
-- T2  node het han trong 10 ngay nua          warranty_status = EXPIRING_SOON, days_remaining = 10
-- T3  node het han trong 90 ngay nua          warranty_status = ACTIVE
-- T4  node khong co du lieu bao hanh          khong xuat hien trong vw_warranty_status
-- T5  usp_list_expiring_warranties @days=30   co T1, T2; khong co T3, T4
-- T6  usp_list_expiring_warranties @days=5    khong co T1 (qua han xa), khong co T2 (10 > 5); co T1 vi EXPIRED luon tinh
-- T7  thu tu sap xep                          T1 (xa nhat ve qua khu) dung truoc T2 khi days=30
-- T8  @days = -1                              loi 51140

USE AR_IMMS;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

DELETE FROM warranty_info WHERE node_id IN (SELECT id FROM nodes WHERE hostname LIKE N'srv-test57-%');
DELETE FROM nodes WHERE hostname LIKE N'srv-test57-%';

DECLARE @rack_id INT = (SELECT MIN(id) FROM racks);
IF @rack_id IS NULL
    THROW 51150, N'FAIL: chua co rack seed (chay 03_seed_data.sql).', 1;

INSERT INTO nodes (rack_id, name, hostname, ip_address, status) VALUES
    (@rack_id, N'TEST57 expired',       N'srv-test57-expired',  N'192.168.10.231', N'MAINTENANCE'),
    (@rack_id, N'TEST57 expiring soon', N'srv-test57-soon',     N'192.168.10.232', N'MAINTENANCE'),
    (@rack_id, N'TEST57 active',        N'srv-test57-active',   N'192.168.10.233', N'MAINTENANCE'),
    (@rack_id, N'TEST57 no warranty',   N'srv-test57-nowty',    N'192.168.10.234', N'MAINTENANCE');

DECLARE @node_expired INT = (SELECT id FROM nodes WHERE hostname = N'srv-test57-expired');
DECLARE @node_soon    INT = (SELECT id FROM nodes WHERE hostname = N'srv-test57-soon');
DECLARE @node_active  INT = (SELECT id FROM nodes WHERE hostname = N'srv-test57-active');
DECLARE @node_nowty   INT = (SELECT id FROM nodes WHERE hostname = N'srv-test57-nowty');

INSERT INTO warranty_info (node_id, vendor, model_number, serial_number, warranty_start, warranty_end) VALUES
    (@node_expired, N'TEST57Vendor', N'M1', N'SN-EXPIRED', DATEADD(YEAR, -3, SYSUTCDATETIME()),
        DATEADD(DAY, -10, SYSUTCDATETIME())),
    (@node_soon,    N'TEST57Vendor', N'M1', N'SN-SOON',    DATEADD(YEAR, -3, SYSUTCDATETIME()),
        DATEADD(DAY, 10, SYSUTCDATETIME())),
    (@node_active,  N'TEST57Vendor', N'M1', N'SN-ACTIVE',  DATEADD(YEAR, -1, SYSUTCDATETIME()),
        DATEADD(DAY, 90, SYSUTCDATETIME()));
-- node_nowty: khong them warranty_info, dung cho T4.

-- T1
IF NOT EXISTS (SELECT 1 FROM dbo.vw_warranty_status
    WHERE node_id = @node_expired AND warranty_status = N'EXPIRED' AND days_remaining = -10)
    THROW 51151, N'FAIL T1: node het han phai co status EXPIRED va days_remaining = -10.', 1;
PRINT N'PASS T1 node het han 10 ngay truoc: EXPIRED, days_remaining = -10';

-- T2
IF NOT EXISTS (SELECT 1 FROM dbo.vw_warranty_status
    WHERE node_id = @node_soon AND warranty_status = N'EXPIRING_SOON' AND days_remaining = 10)
    THROW 51152, N'FAIL T2: node het han trong 10 ngay phai co status EXPIRING_SOON, days_remaining = 10.', 1;
PRINT N'PASS T2 node het han trong 10 ngay: EXPIRING_SOON, days_remaining = 10';

-- T3
IF NOT EXISTS (SELECT 1 FROM dbo.vw_warranty_status WHERE node_id = @node_active AND warranty_status = N'ACTIVE')
    THROW 51153, N'FAIL T3: node het han trong 90 ngay phai co status ACTIVE.', 1;
PRINT N'PASS T3 node het han trong 90 ngay: ACTIVE';

-- T4
IF EXISTS (SELECT 1 FROM dbo.vw_warranty_status WHERE node_id = @node_nowty)
    THROW 51154, N'FAIL T4: node khong co du lieu bao hanh khong duoc xuat hien trong view.', 1;
PRINT N'PASS T4 node khong co du lieu bao hanh: khong xuat hien';

DECLARE @list30 TABLE (warranty_id INT, node_id INT, node_name NVARCHAR(100), hostname NVARCHAR(100),
    vendor NVARCHAR(100), model_number NVARCHAR(100), serial_number NVARCHAR(100),
    warranty_start DATETIME2, warranty_end DATETIME2, days_remaining INT, warranty_status NVARCHAR(20));
INSERT @list30 EXEC dbo.usp_list_expiring_warranties @days = 30;

-- T5
IF NOT EXISTS (SELECT 1 FROM @list30 WHERE node_id = @node_expired)
   OR NOT EXISTS (SELECT 1 FROM @list30 WHERE node_id = @node_soon)
   OR EXISTS (SELECT 1 FROM @list30 WHERE node_id IN (@node_active, @node_nowty))
    THROW 51155, N'FAIL T5: @days=30 phai co node het han va sap het han, khong co node con dai/khong co bao hanh.', 1;
PRINT N'PASS T5 usp_list_expiring_warranties @days=30: co EXPIRED + EXPIRING_SOON, khong co ACTIVE/UNKNOWN';

-- T6: EXPIRED luon xuat hien du @days nho, vi da qua han (days_remaining am <= moi @days >= 0)
DECLARE @list5 TABLE (warranty_id INT, node_id INT, node_name NVARCHAR(100), hostname NVARCHAR(100),
    vendor NVARCHAR(100), model_number NVARCHAR(100), serial_number NVARCHAR(100),
    warranty_start DATETIME2, warranty_end DATETIME2, days_remaining INT, warranty_status NVARCHAR(20));
INSERT @list5 EXEC dbo.usp_list_expiring_warranties @days = 5;
IF NOT EXISTS (SELECT 1 FROM @list5 WHERE node_id = @node_expired)
    THROW 51156, N'FAIL T6: node da EXPIRED phai luon xuat hien du @days nho.', 1;
IF EXISTS (SELECT 1 FROM @list5 WHERE node_id = @node_soon)
    THROW 51157, N'FAIL T6: node con 10 ngay khong duoc xuat hien khi @days=5.', 1;
PRINT N'PASS T6 usp_list_expiring_warranties @days=5: co node da EXPIRED, khong co node con 10 ngay';

-- T7
IF (SELECT TOP 1 node_id FROM @list30 ORDER BY days_remaining ASC) <> @node_expired
    THROW 51158, N'FAIL T7: node het han xa nhat ve qua khu phai dung dau danh sach khi @days=30.', 1;
PRINT N'PASS T7 thu tu sap xep: node het han lau nhat dung truoc';

-- T8
DECLARE @err INT = 0;
BEGIN TRY
    EXEC dbo.usp_list_expiring_warranties @days = -1;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err <> 51140
    THROW 51159, N'FAIL T8: @days am phai bao loi 51140.', 1;
PRINT N'PASS T8 @days = -1 bao loi 51140';

-- Don dep
DELETE FROM warranty_info WHERE node_id IN (@node_expired, @node_soon, @node_active);
DELETE FROM nodes WHERE id IN (@node_expired, @node_soon, @node_active, @node_nowty);
PRINT N'=== HQTCSDL-57: 8 kich ban bao hanh deu PASS, da don du lieu test ===';
GO