-- ============================================================================
-- AR-IMMS: Tạo Database trên SQL Server
-- Hệ thống Giám sát và Bảo trì Cơ sở Hạ tầng Tích hợp Thực tế Tăng cường
-- ============================================================================

USE master;
GO

IF DB_ID(N'AR_IMMS') IS NULL
BEGIN
    CREATE DATABASE AR_IMMS COLLATE Vietnamese_CI_AS;
END
ELSE
BEGIN
    PRINT N'Database AR_IMMS đã tồn tại; giữ nguyên dữ liệu.';
END
GO

USE AR_IMMS;
GO
