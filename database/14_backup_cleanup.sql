-- ============================================================================
-- Job dọn file backup cũ hơn 7 ngày
-- Chạy 01:00 hàng ngày, không dùng chung lịch với job Diff.
-- xp_delete_file là thủ tục không có tài liệu chính thức của Microsoft; nó chỉ
-- xóa file backup SQL Server hợp lệ trong đúng thư mục, theo phần mở rộng.
-- Chưa xác nhận chạy được trên SQL Server Linux/Docker -> bắt buộc test.
-- Nếu không chạy được, thay bằng cron/script PowerShell xóa file trong ./backups
-- trên host và ghi rõ trong báo cáo.
-- ============================================================================
USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'AR_IMMS_Job_Cleanup_Old_Backups')
    EXEC msdb.dbo.sp_delete_job @job_name = N'AR_IMMS_Job_Cleanup_Old_Backups', @delete_unused_schedule = 1;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N'AR_IMMS_Sch_Cleanup_Daily_0100')
    EXEC msdb.dbo.sp_delete_schedule @schedule_name = N'AR_IMMS_Sch_Cleanup_Daily_0100', @force_delete = 1;

EXEC msdb.dbo.sp_add_job
    @job_name = N'AR_IMMS_Job_Cleanup_Old_Backups',
    @enabled = 1,
    @description = N'Xóa file backup Full/Diff (.bak) và Log (.trn) cũ hơn 7 ngày';

-- Bước 1: xóa .bak (Full + Diff) cũ hơn 7 ngày.
EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'AR_IMMS_Job_Cleanup_Old_Backups',
    @step_name = N'Delete old .bak',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'
DECLARE @d DATETIME = DATEADD(DAY, -7, GETDATE());
EXEC master.dbo.xp_delete_file 0, N''/var/opt/mssql/backups/'', N''bak'', @d, 0;',
    @on_success_action = 3;

-- Bước 2: xóa .trn cũ hơn 7 ngày
EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'AR_IMMS_Job_Cleanup_Old_Backups',
    @step_name = N'Delete old .trn',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'
DECLARE @d DATETIME = DATEADD(DAY, -7, GETDATE());
EXEC master.dbo.xp_delete_file 0, N''/var/opt/mssql/backups/'', N''trn'', @d, 0;';

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'AR_IMMS_Sch_Cleanup_Daily_0100',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 010000;

EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'AR_IMMS_Job_Cleanup_Old_Backups',
    @schedule_name = N'AR_IMMS_Sch_Cleanup_Daily_0100';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'AR_IMMS_Job_Cleanup_Old_Backups';
GO

PRINT N'SUCCESS: Đã tạo job dọn backup cũ (01:00 hàng ngày, giữ 7 ngày).';
GO
