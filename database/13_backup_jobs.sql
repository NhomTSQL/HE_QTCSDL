-- ============================================================================
-- SQL Agent Job Full / Differential / Log (HQTCSDL-44)
-- Chiến lược:
--   Full  : 00:00 Chủ nhật hàng tuần   (nền của chuỗi khôi phục)
--   Diff  : 23:00 Thứ 2 - Thứ 7        (chỉ phần thay đổi từ Full gần nhất)
--   Log   : mỗi 30 phút                (mất dữ liệu tối đa ~30 phút)
-- Mỗi job làm 1 batch: BACKUP ... WITH CHECKSUM rồi RESTORE VERIFYONLY cùng file,
-- nên backup hỏng sẽ làm job FAIL thay vì im lặng
-- Yêu cầu: đã chạy 09_backup_recovery_model.sql; Agent bật (MSSQL_AGENT_ENABLED).
-- ============================================================================
USE msdb;
GO

-- Dọn lịch mồ côi của lần chạy trước (job bị xóa thì lịch cùng tên nếu còn sót cũng xóa)
DECLARE @s NVARCHAR(128);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM msdb.dbo.sysschedules WHERE name LIKE N'AR_IMMS[_]Sch[_]%';
OPEN c; FETCH NEXT FROM c INTO @s;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC msdb.dbo.sp_delete_schedule @schedule_name = @s, @force_delete = 1;
    FETCH NEXT FROM c INTO @s;
END
CLOSE c; DEALLOCATE c;
GO

-- ----------------------------------------------------------------------------
-- JOB 1: FULL BACKUP - 00:00 Chủ nhật
-- ----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'AR_IMMS_Job_Full_Backup')
    EXEC msdb.dbo.sp_delete_job @job_name = N'AR_IMMS_Job_Full_Backup', @delete_unused_schedule = 1;

EXEC msdb.dbo.sp_add_job
    @job_name = N'AR_IMMS_Job_Full_Backup',
    @enabled = 1,
    @description = N'Full backup AR_IMMS lúc 00:00 Chủ nhật hàng tuần';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'AR_IMMS_Job_Full_Backup',
    @step_name = N'Full backup + verify',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'
DECLARE @f NVARCHAR(260) = N''/var/opt/mssql/backups/AR_IMMS_Full_''
    + FORMAT(SYSUTCDATETIME(), ''yyyyMMdd_HHmmss'') + N''.bak'';
BACKUP DATABASE AR_IMMS TO DISK = @f
    WITH INIT, CHECKSUM, NAME = N''AR_IMMS Full Backup'';
RESTORE VERIFYONLY FROM DISK = @f WITH CHECKSUM;';

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'AR_IMMS_Sch_Full_Sunday_0000',
    @freq_type = 8,                -- hàng tuần
    @freq_interval = 1,            -- Chủ nhật
    @freq_recurrence_factor = 1,
    @active_start_time = 000000;

EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'AR_IMMS_Job_Full_Backup',
    @schedule_name = N'AR_IMMS_Sch_Full_Sunday_0000';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'AR_IMMS_Job_Full_Backup';
GO

-- ----------------------------------------------------------------------------
-- JOB 2: DIFFERENTIAL BACKUP - 23:00 Thứ 2 đến Thứ 7
-- ----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'AR_IMMS_Job_Diff_Backup')
    EXEC msdb.dbo.sp_delete_job @job_name = N'AR_IMMS_Job_Diff_Backup', @delete_unused_schedule = 1;

EXEC msdb.dbo.sp_add_job
    @job_name = N'AR_IMMS_Job_Diff_Backup',
    @enabled = 1,
    @description = N'Differential backup AR_IMMS lúc 23:00 Thứ 2 - Thứ 7';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'AR_IMMS_Job_Diff_Backup',
    @step_name = N'Differential backup + verify',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'
DECLARE @f NVARCHAR(260) = N''/var/opt/mssql/backups/AR_IMMS_Diff_''
    + FORMAT(SYSUTCDATETIME(), ''yyyyMMdd_HHmmss'') + N''.bak'';
BACKUP DATABASE AR_IMMS TO DISK = @f
    WITH DIFFERENTIAL, INIT, CHECKSUM, NAME = N''AR_IMMS Differential Backup'';
RESTORE VERIFYONLY FROM DISK = @f WITH CHECKSUM;';

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'AR_IMMS_Sch_Diff_MonSat_2300',
    @freq_type = 8,
    @freq_interval = 126,          -- T2..T7 = 2+4+8+16+32+64
    @freq_recurrence_factor = 1,
    @active_start_time = 230000;

EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'AR_IMMS_Job_Diff_Backup',
    @schedule_name = N'AR_IMMS_Sch_Diff_MonSat_2300';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'AR_IMMS_Job_Diff_Backup';
GO

-- ----------------------------------------------------------------------------
-- JOB 3: TRANSACTION LOG BACKUP - mỗi 30 phút
-- (Fail nếu chưa có Full backup nào: chạy Full thủ công 1 lần trước.)
-- ----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'AR_IMMS_Job_Log_Backup')
    EXEC msdb.dbo.sp_delete_job @job_name = N'AR_IMMS_Job_Log_Backup', @delete_unused_schedule = 1;

EXEC msdb.dbo.sp_add_job
    @job_name = N'AR_IMMS_Job_Log_Backup',
    @enabled = 1,
    @description = N'Transaction log backup AR_IMMS mỗi 30 phút';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'AR_IMMS_Job_Log_Backup',
    @step_name = N'Log backup + verify',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'
DECLARE @f NVARCHAR(260) = N''/var/opt/mssql/backups/AR_IMMS_Log_''
    + FORMAT(SYSUTCDATETIME(), ''yyyyMMdd_HHmmss'') + N''.trn'';
BACKUP LOG AR_IMMS TO DISK = @f
    WITH INIT, CHECKSUM, NAME = N''AR_IMMS Log Backup'';
RESTORE VERIFYONLY FROM DISK = @f WITH CHECKSUM;';

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'AR_IMMS_Sch_Log_Every30Min',
    @freq_type = 4,                -- hàng ngày
    @freq_interval = 1,
    @freq_subday_type = 4,         -- đơn vị phút
    @freq_subday_interval = 30,
    @active_start_time = 000000,
    @active_end_time = 235959;

EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'AR_IMMS_Job_Log_Backup',
    @schedule_name = N'AR_IMMS_Sch_Log_Every30Min';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'AR_IMMS_Job_Log_Backup';
GO

PRINT N'SUCCESS: Đã tạo 3 SQL Agent job backup (Full, Diff, Log) cho AR_IMMS.';
GO
