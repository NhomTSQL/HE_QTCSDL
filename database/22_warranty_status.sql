-- 22_warranty_status.sql
-- HQTCSDL-57: view + procedure trang thai bao hanh, liet ke node sap het han.
-- Chay lai nhieu lan an toan (CREATE OR ALTER).
-- Test case: database/23_test_warranty_status.sql.

USE AR_IMMS;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- View: trang thai bao hanh cua moi node co warranty_info. Chi node co du lieu bao hanh moi xuat hien.
-- days_remaining < 0 nghia la da het han. status: EXPIRED / EXPIRING_SOON (<=30 ngay) / ACTIVE / UNKNOWN (thieu warranty_end).
-- Test case: node het han 10 ngay truoc -> status EXPIRED, days_remaining = -10.
CREATE OR ALTER VIEW vw_warranty_status AS
SELECT w.id AS warranty_id, w.node_id, n.name AS node_name, n.hostname,
       w.vendor, w.model_number, w.serial_number, w.warranty_start, w.warranty_end,
       DATEDIFF(DAY, CAST(SYSUTCDATETIME() AS DATE), CAST(w.warranty_end AS DATE)) AS days_remaining,
       CASE
           WHEN w.warranty_end IS NULL THEN N'UNKNOWN'
           WHEN w.warranty_end < SYSUTCDATETIME() THEN N'EXPIRED'
           WHEN w.warranty_end <= DATEADD(DAY, 30, SYSUTCDATETIME()) THEN N'EXPIRING_SOON'
           ELSE N'ACTIVE'
       END AS warranty_status
FROM warranty_info w
INNER JOIN nodes n ON n.id = w.node_id;
GO

-- SP: liet ke node sap het bao hanh trong @days ngay toi (mac dinh 30), gom ca node da het han.
-- Sap xep gan het han nhat len dau. Node khong co du lieu bao hanh (UNKNOWN) khong xuat hien.
-- Test case: @days = 30, node het han trong 10 ngay nua -> co trong danh sach; node con 60 ngay -> khong co.
CREATE OR ALTER PROCEDURE usp_list_expiring_warranties
    @days INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @days < 0
        THROW 51140, N'days phai >= 0.', 1;

    SELECT warranty_id, node_id, node_name, hostname, vendor, model_number, serial_number,
           warranty_start, warranty_end, days_remaining, warranty_status
    FROM dbo.vw_warranty_status
    WHERE warranty_status IN (N'EXPIRED', N'EXPIRING_SOON')
      AND days_remaining <= @days
    ORDER BY days_remaining ASC;
END;
GO

PRINT N'=== HQTCSDL-57: view/SP trang thai bao hanh san sang ===';
GO