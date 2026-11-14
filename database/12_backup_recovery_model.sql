-- ============================================================================
-- Chuyển Recovery Model sang FULL
-- Lý do: BACKUP LOG chỉ chạy được khi DB ở FULL;
-- ============================================================================
USE master;
GO

IF DB_ID(N'AR_IMMS') IS NULL
BEGIN
    PRINT N'WARNING: Không tìm thấy database AR_IMMS. Chạy 01_create_database.sql trước.';
END
ELSE
BEGIN
    ALTER DATABASE AR_IMMS SET RECOVERY FULL WITH NO_WAIT;
    PRINT N'SUCCESS: AR_IMMS đã ở RECOVERY FULL.';
END
GO

-- Kiểm tra nhanh: cột recovery_model_desc phải là FULL
SELECT name, recovery_model_desc FROM sys.databases WHERE name = N'AR_IMMS';
GO
