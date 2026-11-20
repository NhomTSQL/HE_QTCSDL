-- ============================================================================
-- AR-IMMS: SQL Server Least-Privilege Login, User & Role Verification
-- Tạo user ứng dụng ar_imms_app chỉ có quyền EXECUTE Stored Procedure,
-- không thể đọc/sửa/xóa trực tiếp bất kỳ bảng nào.
-- Không chứa mật khẩu hardcode: truyền sqlcmd -v AR_IMMS_APP_PASSWORD="..."
-- nếu muốn tạo Login thật; mặc định tạo USER WITHOUT LOGIN để kiểm thử.
-- ============================================================================

USE AR_IMMS;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

:setvar AR_IMMS_APP_PASSWORD ""

DECLARE @pwd NVARCHAR(256) = N'$(AR_IMMS_APP_PASSWORD)';

IF NULLIF(LTRIM(RTRIM(@pwd)), N'') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'ar_imms_app')
    BEGIN
        DECLARE @create_login NVARCHAR(MAX) =
            N'CREATE LOGIN [ar_imms_app] WITH PASSWORD = N'''
            + REPLACE(@pwd, N'''', N'''''')
            + N''', CHECK_POLICY = ON, DEFAULT_DATABASE = [AR_IMMS];';
        EXEC sys.sp_executesql @create_login;
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'ar_imms_app')
        CREATE USER [ar_imms_app] FOR LOGIN [ar_imms_app];
END
ELSE
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'ar_imms_app')
        CREATE USER [ar_imms_app] WITHOUT LOGIN;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'db_ar_imms_executor' AND type = N'R')
    CREATE ROLE [db_ar_imms_executor];
GO

GRANT EXECUTE ON SCHEMA::dbo TO [db_ar_imms_executor];
DENY UPDATE, DELETE ON dbo.audit_logs TO [db_ar_imms_executor];
ALTER ROLE [db_ar_imms_executor] ADD MEMBER [ar_imms_app];
GO

-- ═══════════════════════════════════════════════════════════════════
-- TỰ KIỂM CHỨNG PHÂN QUYỀN TỐI THIỂU (EXECUTE AS USER)
-- ═══════════════════════════════════════════════════════════════════
EXECUTE AS USER = N'ar_imms_app';

EXEC dbo.usp_health_check;
EXEC dbo.usp_list_nodes_latest;

DECLARE @err INT;

BEGIN TRY
    EXEC(N'SELECT TOP (1) id, username FROM dbo.users;');
    THROW 51098, N'FAIL: ar_imms_app should not be allowed to SELECT dbo.users directly.', 1;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER();
    IF @err <> 229 THROW;
    PRINT N'PASS: Direct SELECT on dbo.users denied with SQL error 229.';
END CATCH;

BEGIN TRY
    EXEC(N'DELETE FROM dbo.audit_logs WHERE id = 1;');
    THROW 51099, N'FAIL: ar_imms_app should not be allowed to DELETE dbo.audit_logs.', 1;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER();
    IF @err <> 229 THROW;
    PRINT N'PASS: Direct DELETE on dbo.audit_logs denied with SQL error 229.';
END CATCH;

REVERT;
GO

PRINT N'=== 23_least_privilege_login.sql verified successfully ===';
GO
