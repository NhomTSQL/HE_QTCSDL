# Test case Backup/Restore

Môi trường: SQL Server 2022 Developer trong Docker, Agent bật,
Thứ tự script: `09` → `10` → `11` → (test) → `12`. Mỗi script chạy lại được.

| Mã | Mục tiêu | Các bước | Kết quả mong đợi |
|---|---|---|---|
| TC-01 | Recovery model = FULL | Chạy `09_backup_recovery_model.sql`; chạy `SELECT name, recovery_model_desc FROM sys.databases WHERE name = N'AR_IMMS';` | `recovery_model_desc = FULL` |
| TC-02 | Tạo đủ 4 job, chạy lại không lỗi | Chạy `10_backup_jobs.sql` và `11_backup_cleanup.sql` **2 lần liên tiếp**; chạy `SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name LIKE N'AR_IMMS[_]Job[_]%';` | Cả 2 lượt không lỗi; đúng 4 job: `AR_IMMS_Job_Full_Backup`, `_Diff_Backup`, `_Log_Backup`, `_Cleanup_Old_Backups`, `enabled = 1` |
| TC-03 | Job sinh file trong `backups/` | Chạy thủ công theo thứ tự: `EXEC msdb.dbo.sp_start_job N'AR_IMMS_Job_Full_Backup';` rồi `..._Diff_Backup`, rồi `..._Log_Backup`. Xem thư mục `backups/` trên host | Có `AR_IMMS_Full_*.bak`, `AR_IMMS_Diff_*.bak`, `AR_IMMS_Log_*.trn`|
| TC-03b | Job chạy **theo lịch** | Tạm đổi lịch job Log chạy mỗi 1 phút: `EXEC msdb.dbo.sp_update_schedule @name = N'AR_IMMS_Sch_Log_Every30Min', @freq_subday_type = 4, @freq_subday_interval = 1;` Chờ 3 phút, xem `backups/` và job history. Sau đó trả lại: `@freq_subday_interval = 30`| Xuất hiện ≥ 2 file `.trn` mới do lịch tự chạy, không bấm tay |
| TC-04 | Job dọn file cũ | Chạy thủ công `EXEC msdb.dbo.sp_start_job N'AR_IMMS_Job_Cleanup_Old_Backups';` rồi xem job history và thư mục `backups/`. (Khó giả lập file cũ 7 ngày vì `xp_delete_file` đọc ngày trong header backup, nên chủ yếu kiểm tra job chạy được và không xóa nhầm.) | Job Succeeded; **file mới (< 7 ngày) không bị xóa**. Nếu job báo lỗi, ghi rõ lỗi và dùng phương án xóa ngoài (cron/PowerShell) |
| TC-05 | Restore chuỗi Full → Diff → Log vào DB thử | Chạy `12_restore_disaster_recovery.sql` nguyên file (mặc định không cần sửa gì: script tự chọn Full mới nhất, Diff, các Log theo thứ tự).| Bảng chuỗi liệt kê đúng thứ tự Full → Diff → Log; `AR_IMMS_RestoreTest` ở `ONLINE`; `DBCC CHECKDB` không lỗi; `source_tables = restored_tables` |