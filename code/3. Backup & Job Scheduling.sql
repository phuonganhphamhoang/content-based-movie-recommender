-- Tạo ổ đĩa để lưu backup
EXECUTE master.dbo.xp_create_subdir 'D:\SQLBackups\Full'
EXECUTE master.dbo.xp_create_subdir 'D:\SQLBackups\Diff'

-- Tạo bảng lưu log cho backup
CREATE TABLE LogBackup (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    BackupType NVARCHAR(50),       -- Loại backup: FULL, DIFFERENTIAL
    BackupDate DATETIME,           -- Thời điểm backup
    BackupFilePath NVARCHAR(200),  -- Đường dẫn file backup
    Status NVARCHAR(50)            -- Trạng thái backup: Success, Failed, etc.
);

-- Thủ tục Full Backup cho database Movies
CREATE PROCEDURE FullBackup
AS
BEGIN
    DECLARE @BackupFileName NVARCHAR(200);
    DECLARE @BackupPath NVARCHAR(200) = N'D:\SQLBackups\Full\'; -- Đường dẫn thư mục sao lưu
    DECLARE @Status NVARCHAR(50) = 'Success';

    -- Tạo tên file backup full với timestamp
    SET @BackupFileName = @BackupPath + N'Movies_Full_' + FORMAT(GETDATE(), 'yyyyMMdd_HHmm') + N'.bak';

    BEGIN TRY
        -- Thực hiện sao lưu full
        BACKUP DATABASE Movies
        TO DISK = @BackupFileName
        WITH INIT, COMPRESSION, STATS = 10;
    END TRY
    BEGIN CATCH
        -- Nếu backup thất bại
        SET @Status = 'Failed';
    END CATCH

    -- Ghi lại lịch sử vào bảng LogBackup
    INSERT INTO LogBackup (BackupType, BackupDate, BackupFilePath, Status)
    VALUES ('FULL', GETDATE(), @BackupFileName, @Status);

    PRINT 'Full backup completed with status: ' + @Status;
END;
GO

-- Thủ tục Differential Backup cho database Movies
CREATE PROCEDURE DiffBackup
AS
BEGIN
    DECLARE @BackupFileName NVARCHAR(200);
    DECLARE @BackupPath NVARCHAR(200) = N'D:\SQLBackups\Diff\'; -- Đường dẫn thư mục sao lưu
    DECLARE @Status NVARCHAR(50) = 'Success';

    -- Tạo tên file backup differential với timestamp
    SET @BackupFileName = @BackupPath + N'Movies_Diff_' + FORMAT(GETDATE(), 'yyyyMMdd_HHmm') + N'.bak';

    BEGIN TRY
        -- Thực hiện sao lưu differential
        BACKUP DATABASE Movies 
        TO DISK = @BackupFileName
        WITH DIFFERENTIAL, COMPRESSION, STATS = 10;
    END TRY
    BEGIN CATCH
        -- Nếu backup thất bại
        SET @Status = 'Failed';
    END CATCH

    -- Ghi lại lịch sử vào bảng LogBackup
    INSERT INTO LogBackup (BackupType, BackupDate, BackupFilePath, Status)
    VALUES ('DIFFERENTIAL', GETDATE(), @BackupFileName, @Status);

    PRINT 'Differential backup completed with status: ' + @Status;
END;
GO

-- Tạo job cho FullBackup
BEGIN TRANSACTION
    DECLARE @JobID NVARCHAR(36);

    -- Xóa job cũ và schedule nếu tồn tại
    IF EXISTS (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'Monthly_FullBackup')
        EXEC msdb.dbo.sp_delete_job @job_name = N'Monthly_FullBackup', @delete_unused_schedule=1;

	IF EXISTS (SELECT schedule_id FROM msdb.dbo.sysschedules WHERE name = N'WeeklyDiffBackupSchedule')
		EXEC msdb.dbo.sp_delete_schedule @schedule_name = N'MonthlyFullBackupSchedule';

    -- Tạo job mới cho Full Backup hàng tháng
    EXEC msdb.dbo.sp_add_job
        @job_name = N'Monthly_FullBackup',
        @enabled = 1,
        @description = N'Monthly Full Backup for Movies database',
        @job_id = @JobID OUTPUT;

    -- Thêm job step để gọi thủ tục FullBackup
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobID,
        @step_name = N'Execute Full Backup',
        @subsystem = N'TSQL',
        @command = N'EXEC FullBackup',
        @database_name = N'Movies';

    -- Tạo schedule cho job chạy vào ngày đầu tiên của mỗi tháng lúc 00:00:00
    EXEC msdb.dbo.sp_add_schedule
        @schedule_name = N'MonthlyFullBackupSchedule',
        @freq_type = 16,              -- Monthly
        @freq_interval = 1,           -- Ngày đầu tiên của tháng
        @freq_recurrence_factor = 1,  -- Thực hiện hàng tháng (bắt buộc phải có)
        @active_start_time = 000000;  -- 00:00:00

	-- Gán schedule trực tiếp
	EXEC msdb.dbo.sp_attach_schedule @job_id = @JobID, @schedule_name = N'MonthlyFullBackupSchedule';

	-- Gán job vào server cụ thể
	EXEC msdb.dbo.sp_add_jobserver
		@job_id = @JobID, 
		@server_name = N'LAPTOP-80LB8QKQ'; 

COMMIT TRANSACTION;
GO

-- Tạo job cho DiffBackup
BEGIN TRANSACTION
    DECLARE @JobID NVARCHAR(36);

    -- Xóa job cũ và schedule cũ nếu tồn tại
    IF EXISTS (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'Weekly_DiffBackup')
        EXEC msdb.dbo.sp_delete_job @job_name = N'Weekly_DiffBackup', @delete_unused_schedule=1;

	IF EXISTS (SELECT schedule_id FROM msdb.dbo.sysschedules WHERE name = N'WeeklyDiffBackupSchedule')
		EXEC msdb.dbo.sp_delete_schedule @schedule_name = N'WeeklyDiffBackupSchedule';

    -- Tạo job mới cho DiffBackup hàng tuần
    EXEC msdb.dbo.sp_add_job
        @job_name = N'Weekly_DiffBackup',
        @enabled = 1,
        @description = N'Weekly Differential Backup for Movies database',
        @job_id = @JobID OUTPUT;

    -- Thêm job step để gọi thủ tục DiffBackup
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobID,
        @step_name = N'Execute Differential Backup',
        @subsystem = N'TSQL',
        @command = N'EXEC DiffBackup',
        @database_name = N'Movies';

    -- Tạo schedule cho job chạy hàng tuần vào Chủ nhật lúc 01:00:00
    EXEC msdb.dbo.sp_add_schedule
        @schedule_name = N'WeeklyDiffBackupSchedule',
        @freq_type = 8,                -- Weekly
        @freq_interval = 1,            -- Chạy vào Chủ nhật
        @freq_recurrence_factor = 1,   -- Thực hiện hàng tuần (bắt buộc phải có)
        @active_start_time = 010000;   -- 01:00:00

	-- Gán schedule trực tiếp
	EXEC msdb.dbo.sp_attach_schedule @job_id = @JobID, @schedule_name = N'WeeklyDiffBackupSchedule';

	-- Gán job vào server cụ thể
	EXEC msdb.dbo.sp_add_jobserver
		@job_id = @JobID, 
		@server_name = N'LAPTOP-80LB8QKQ'; 

COMMIT TRANSACTION;
GO

-- Kích hoạt xp_cmdshell
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1;
RECONFIGURE;

-- Thủ tục xóa backups
CREATE PROCEDURE CleanupOldBackups
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Khai báo các biến cần thiết
    DECLARE @FullBackupPath NVARCHAR(200) = N'D:\SQLBackups\Full\';
    DECLARE @DiffBackupPath NVARCHAR(200) = N'D:\SQLBackups\Diff\';
    DECLARE @DeleteFullBackupAfterDays INT = 60;  -- Full Backup giữ lại trong 60 ngày
    DECLARE @DeleteDiffBackupAfterDays INT = 14;  -- Diff Backup giữ lại trong 14 ngày
    DECLARE @Status NVARCHAR(50) = 'Success';
    DECLARE @ErrorMessage NVARCHAR(MAX) = NULL;
    DECLARE @JobName NVARCHAR(100);
    
    BEGIN TRY
        -- Lấy tên job thực thi hiện tại
        SELECT @JobName = N'Weekly_CleanupOldBackups' 
        FROM msdb.dbo.sysjobs j 
        INNER JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id 
        WHERE ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.sysjobactivity);

        -- Nếu không có tên job, gán là 'Manual Execution'
        IF @JobName IS NULL 
            SET @JobName = 'Manual Execution';
        
        -- Xóa full backups cũ hơn 60 ngày
        EXEC xp_cmdshell 'forfiles /p "D:\SQLBackups\Full" /s /m *.bak /d -60 /c "cmd /c del @path"';
        
        -- Xóa differential backups cũ hơn 14 ngày
        EXEC xp_cmdshell 'forfiles /p "D:\SQLBackups\Diff" /s /m *.bak /d -14 /c "cmd /c del @path"';
    END TRY
    BEGIN CATCH
        -- Nếu có lỗi, gán trạng thái là 'Failed' và lưu thông báo lỗi
        SET @Status = 'Failed';
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR (@ErrorMessage, 16, 1);
    END CATCH
    
    -- Log kết quả vào bảng LogBackup
    INSERT INTO LogBackup (BackupType, BackupDate, BackupFilePath, Status)
    VALUES ('CLEANUP', GETDATE(), 'N/A', @Status);
    -- Nếu có lỗi, ném lỗi ra ngoài
    IF @Status = 'Failed'
        THROW 51000, @ErrorMessage, 1;
    
    RETURN 0;
END;
GO

-- Tạo job cho CleanupOldBackups
BEGIN TRANSACTION
    DECLARE @JobID NVARCHAR(36), @ScheduleID INT;

    -- Xóa job cũ nếu đã tồn tại
    IF EXISTS (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'Weekly_CleanupOldBackups')
        EXEC msdb.dbo.sp_delete_job @job_name = N'Weekly_CleanupOldBackups', @delete_unused_schedule=1;

    -- Tạo job mới cho việc dọn dẹp backup cũ hàng tuần
    EXEC msdb.dbo.sp_add_job
        @job_name = N'Weekly_CleanupOldBackups',
        @enabled = 1,
        @description = N'Weekly Cleanup of Old Backup Files',
        @job_id = @JobID OUTPUT;

    -- Thêm bước job để gọi thủ tục CleanupOldBackups
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobID,
        @step_name = N'Execute CleanupOldBackups',
        @subsystem = N'TSQL',
        @command = N'EXEC CleanupOldBackups;',
        @database_name = N'Movies';

    -- Tạo schedule để chạy job vào Chủ nhật hàng tuần lúc 02:00 sáng
    EXEC msdb.dbo.sp_add_schedule
        @schedule_name = N'WeeklyCleanupSchedule',
        @freq_type = 1,                -- Chạy 1 lần
        @freq_interval = 1,            -- Ngày đầu tiên
        @freq_recurrence_factor = 2,   -- 2 ngày chạy 1 lần
        @active_start_time = 020000,   -- 02:00:00 sáng
        @schedule_id = @ScheduleID OUTPUT;

    -- Gán schedule vào job
    EXEC msdb.dbo.sp_attach_schedule @job_id = @JobID,	@schedule_id = @ScheduleID;
    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobID;
COMMIT TRANSACTION;
GO

-- Restore database
USE master
RESTORE DATABASE Movies 
FROM DISK = 'D:\SQLBackups\Full\Movies_Full_20241115_2313.bak'
WITH REPLACE;

-- Xem lịch sử backup
SELECT * FROM LogBackup

