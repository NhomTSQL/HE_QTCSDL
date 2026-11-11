-- 10_agent_job_heartbeat.sql
-- HQTCSDL-31: SQL Server Agent Job kiem tra heartbeat. Chay lai nhieu lan an toan
-- (xoa job cu neu co roi tao lai). Can SQL Server Agent dang chay (MSSQL_AGENT_ENABLED=true).
-- Job: moi 15 giay goi usp_check_stale_nodes @stale_timeout_seconds = 90.
-- Test case: node mat heartbeat > 90 giay -> UNAVAILABLE va co dung 1 alert NODE_UNAVAILABLE
-- (xem database/11_test_heartbeat_job.sql).

USE msdb;
GO

DECLARE @job_name SYSNAME = N'AR_IMMS_Check_Stale_Nodes';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @job_name)
    EXEC msdb.dbo.sp_delete_job @job_name = @job_name, @delete_unused_schedule = 1;

EXEC msdb.dbo.sp_add_job
    @job_name = @job_name,
    @enabled = 1,
    @description = N'AR-IMMS: danh dau node UNAVAILABLE va tao alert khi mat heartbeat qua 90 giay.';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = @job_name,
    @step_name = N'Run usp_check_stale_nodes',
    @subsystem = N'TSQL',
    @database_name = N'AR_IMMS',
    @command = N'EXEC dbo.usp_check_stale_nodes @stale_timeout_seconds = 90;',
    @on_success_action = 1,
    @on_fail_action = 2;

EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @job_name,
    @name = N'Every 15 seconds',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 2,
    @freq_subday_interval = 15,
    @active_start_time = 0;

EXEC msdb.dbo.sp_add_jobserver
    @job_name = @job_name,
    @server_name = N'(LOCAL)';

PRINT N'=== Da tao SQL Agent Job AR_IMMS_Check_Stale_Nodes (moi 15 giay) ===';
GO