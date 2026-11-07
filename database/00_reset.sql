-- 00_reset.sql
-- Xoa sach database AR_IMMS de chay lai toan bo script tu dau.
-- CANH BAO: lenh nay xoa TOAN BO du lieu. Chi dung tren moi truong dev.

USE master;
GO

IF DB_ID(N'AR_IMMS') IS NOT NULL
BEGIN
    ALTER DATABASE AR_IMMS SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE AR_IMMS;
    PRINT N'=== Da xoa database AR_IMMS ===';
END
ELSE
    PRINT N'=== Database AR_IMMS chua ton tai, khong can xoa ===';
GO