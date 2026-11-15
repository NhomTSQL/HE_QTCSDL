-- ============================================================================
-- Kịch bản khôi phục
-- Khôi phục chuỗi Full -> Diff -> Log vào DB.
-- KHÔNG ghi đè AR_IMMS đang chạy. Thứ tự: các bước đầu WITH NORECOVERY,
-- bước cuối WITH RECOVERY để mở DB.
-- Cách dùng:
--   1) Chạy phần A để xem lịch sử backup, chọn tên file.
--   2) Sửa 3 biến @Full, @Diff, @Log1 (thêm RESTORE LOG nếu có nhiều file .trn,
--      theo đúng thứ tự thời gian; chỉ file cuối cùng mới WITH RECOVERY).
--   3) Chạy phần B. Phần C kiểm tra kết quả.
-- Thảm họa thật (AR_IMMS mất hẳn): làm tương tự nhưng restore thẳng tên AR_IMMS.
-- ============================================================================
USE master;
GO

-- ---- Phần A: lịch sử backup gần nhất để chọn file ----
SELECT TOP (20)
       bs.backup_finish_date,
       CASE bs.type WHEN 'D' THEN 'Full' WHEN 'I' THEN 'Diff' WHEN 'L' THEN 'Log' END AS backup_type,
       bmf.physical_device_name
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'AR_IMMS'
ORDER BY bs.backup_finish_date DESC;
GO

-- ---- Phần B: restore vào DB thử ----
DECLARE @Full NVARCHAR(260) = N'/var/opt/mssql/backups/AR_IMMS_Full_YYYYMMDD_HHMMSS.bak';  -- Sua
DECLARE @Diff NVARCHAR(260) = N'/var/opt/mssql/backups/AR_IMMS_Diff_YYYYMMDD_HHMMSS.bak';  -- SỬA
DECLARE @Log1 NVARCHAR(260) = N'/var/opt/mssql/backups/AR_IMMS_Log_YYYYMMDD_HHMMSS.trn';   -- SỬA
-- Coppy dòng Log1 r sửa lại nếu có nhiều file Log theo đúng thứ tự thời gian

-- Tên logical file của DB gốc (để MOVE sang đường dẫn khác, tránh đè file AR_IMMS)
DECLARE @DataLogical SYSNAME = (SELECT name FROM sys.master_files WHERE database_id = DB_ID(N'AR_IMMS') AND type = 0);
DECLARE @LogLogical  SYSNAME = (SELECT name FROM sys.master_files WHERE database_id = DB_ID(N'AR_IMMS') AND type = 1);

-- Xóa DB thử cũ
IF DB_ID(N'AR_IMMS_RestoreTest') IS NOT NULL
BEGIN
    ALTER DATABASE AR_IMMS_RestoreTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE AR_IMMS_RestoreTest;
END

DECLARE @sql NVARCHAR(MAX);

-- B1: Full, giữ NORECOVERY để còn restore tiếp
SET @sql = N'RESTORE DATABASE AR_IMMS_RestoreTest FROM DISK = N''' + @Full + N'''
  WITH MOVE N''' + @DataLogical + N''' TO N''/var/opt/mssql/data/AR_IMMS_RestoreTest.mdf'',
       MOVE N''' + @LogLogical  + N''' TO N''/var/opt/mssql/data/AR_IMMS_RestoreTest_log.ldf'',
       NORECOVERY, CHECKSUM;';
EXEC sys.sp_executesql @sql;

-- B2: Diff mới nhất sau Full đó
SET @sql = N'RESTORE DATABASE AR_IMMS_RestoreTest FROM DISK = N''' + @Diff + N''' WITH NORECOVERY, CHECKSUM;';
EXEC sys.sp_executesql @sql;

-- B3: Log theo thứ tự thời gian; file cuối cùng WITH RECOVERY để mở DB
SET @sql = N'RESTORE LOG AR_IMMS_RestoreTest FROM DISK = N''' + @Log1 + N''' WITH RECOVERY;';
EXEC sys.sp_executesql @sql;
GO
-- Coppy 3 dòng trên rồi sửa lại nếu có nhiều Log

-- ---- Phần C: kiểm tra DB đã khôi phục ----
SELECT name, state_desc FROM sys.databases WHERE name = N'AR_IMMS_RestoreTest';  -- ONLINE
DBCC CHECKDB (AR_IMMS_RestoreTest) WITH NO_INFOMSGS;                              -- không lỗi
SELECT (SELECT COUNT(*) FROM AR_IMMS.sys.tables)            AS source_tables,
       (SELECT COUNT(*) FROM AR_IMMS_RestoreTest.sys.tables) AS restored_tables;  -- bằng nhau
GO