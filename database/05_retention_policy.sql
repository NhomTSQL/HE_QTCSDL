-- ============================================================================
-- AR-IMMS: Telemetry Retention Policy
-- Xóa dữ liệu telemetry cũ hơn N ngày để kiểm soát dung lượng
-- Chạy định kỳ bằng SQL Server Agent Job hoặc backend scheduler
-- ============================================================================

USE AR_IMMS;
GO

CREATE OR ALTER PROCEDURE sp_cleanup_old_telemetry
    @retention_days INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @retention_days <= 0
        THROW 50001, N'@retention_days must be greater than zero.', 1;

    DECLARE @cutoff DATETIME2 = DATEADD(DAY, -@retention_days, SYSUTCDATETIME());
    DECLARE @deleted_count INT = 0;

    -- Xóa theo batch 10,000 row để tránh lock table quá lâu
    WHILE 1 = 1
    BEGIN
        DELETE TOP (10000)
        FROM telemetry_metrics
        WHERE timestamp < @cutoff;

        SET @deleted_count = @deleted_count + @@ROWCOUNT;

        IF @@ROWCOUNT < 10000
            BREAK;
    END

    -- Ghi audit
    INSERT INTO audit_logs (username, action, target_entity, details_json, timestamp)
    VALUES (N'SYSTEM', N'TELEMETRY_CLEANUP', N'telemetry_metrics',
            N'{"retention_days":' + CAST(@retention_days AS NVARCHAR(10))
                + N',"deleted_rows":' + CAST(@deleted_count AS NVARCHAR(20)) + N'}',
            SYSUTCDATETIME());

    SELECT @deleted_count AS rows_deleted, @retention_days AS retention_days;
END;
GO

-- Test case: Execute with @retention_days = 30 when one older telemetry row
-- exists; expect that row to be deleted and the deleted count returned.
PRINT N'=== Tạo Retention Policy thành công ===';
GO
