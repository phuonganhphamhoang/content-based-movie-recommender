-- 1. Cập nhật thủ tục tạo Login và User để chỉ định cơ sở dữ liệu
CREATE PROCEDURE CreateLoginAndUser
    @DatabaseName NVARCHAR(50),
    @LoginName NVARCHAR(50),
    @Password NVARCHAR(50),
    @UserName NVARCHAR(50)
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX);

    -- Tạo login
    SET @SQL = 'CREATE LOGIN ' + QUOTENAME(@LoginName) + ' WITH PASSWORD = ' + QUOTENAME(@Password, '''') + 
               ', CHECK_POLICY = ON, CHECK_EXPIRATION = ON;';
    EXEC sp_executesql @SQL;

    -- Tạo user trong cơ sở dữ liệu chỉ định
    SET @SQL = 'USE ' + QUOTENAME(@DatabaseName) + ';
               CREATE USER ' + QUOTENAME(@UserName) + ' FOR LOGIN ' + QUOTENAME(@LoginName) + ';';
    EXEC sp_executesql @SQL;
END;

-- 2. Cập nhật thủ tục phân quyền
CREATE PROCEDURE AssignRole_AD_DA
    @DatabaseName NVARCHAR(100), -- Tên cơ sở dữ liệu
    @RoleType NVARCHAR(50),      -- Loại vai trò (Admin, DA)
    @UserName NVARCHAR(50)       -- Tên người dùng
AS
BEGIN
    BEGIN TRY
        -- Kiểm tra nếu cơ sở dữ liệu tồn tại
        IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = @DatabaseName)
        BEGIN
            PRINT N'Cơ sở dữ liệu không tồn tại!';
            RETURN;
        END

        -- Sử dụng cơ sở dữ liệu
        DECLARE @SQL NVARCHAR(MAX);
        SET @SQL = N'USE ' + QUOTENAME(@DatabaseName) + ';';

        -- Phân quyền theo vai trò
        IF @RoleType = 'Admin'
        BEGIN
            -- Thêm người dùng vào vai trò db_owner
            SET @SQL = @SQL + '
            ALTER ROLE db_owner ADD MEMBER ' + QUOTENAME(@UserName) + ';';
        END
        ELSE IF @RoleType = 'DA'
        BEGIN
            -- Chỉ cấp quyền đọc
            SET @SQL = @SQL + '
            ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@UserName) + ';';
        END
        ELSE
        BEGIN
            PRINT N'Loại vai trò không hợp lệ!';
            RETURN;
        END

        -- In thông báo hoàn thành
        SET @SQL = @SQL + '
        PRINT N''Đã cấp quyền thành công cho người dùng '' + ' + QUOTENAME(@UserName) + ';';

        -- Thực thi lệnh SQL
        EXEC sp_executesql @SQL;

    END TRY
    BEGIN CATCH
        -- Bắt lỗi và hiển thị thông báo lỗi
        PRINT N'Đã xảy ra lỗi khi cấp quyền:';
        PRINT ERROR_MESSAGE();
    END CATCH
END;

CREATE PROCEDURE AssignRole_DE
    @DatabaseName NVARCHAR(100),
    @RoleType NVARCHAR(50),
    @UserName NVARCHAR(50)
AS
BEGIN
    BEGIN TRY
        -- Khai báo biến SQL động
        DECLARE @SQL NVARCHAR(MAX);
        SET @SQL = 'USE ' + QUOTENAME(@DatabaseName) + ';';

        -- Kiểm tra nếu vai trò là 'DE'
        IF @RoleType = 'DE'
        BEGIN
            -- Cấp quyền đọc (db_datareader)
            SET @SQL = @SQL + '
            ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@UserName) + ';
            PRINT N''Thêm ' + @UserName + ' vào db_datareader thành công!'';';

            -- Cấp quyền ghi (db_datawriter)
            SET @SQL = @SQL + '
            ALTER ROLE db_datawriter ADD MEMBER ' + QUOTENAME(@UserName) + ';
            PRINT N''Thêm ' + @UserName + ' vào db_datawriter thành công!'';';

            -- Cấp quyền quản lý schema và các lệnh DDL (db_ddladmin)
            SET @SQL = @SQL + '
            ALTER ROLE db_ddladmin ADD MEMBER ' + QUOTENAME(@UserName) + ';
            PRINT N''Thêm ' + @UserName + ' vào db_ddladmin thành công!'';';

            -- Cấp quyền EXECUTE
            SET @SQL = @SQL + '
            GRANT EXECUTE TO ' + QUOTENAME(@UserName) + ';
            PRINT N''Cấp quyền EXECUTE cho ' + @UserName + ' thành công!'';';
        END

        -- Thực thi câu lệnh SQL động
        EXEC sp_executesql @SQL;
    END TRY
    BEGIN CATCH
        -- Xử lý lỗi nếu có
        PRINT N'Lỗi khi thực thi: ' + ERROR_MESSAGE();
    END CATCH
END;

-- 3. Cập nhật thủ tục hiển thị quyền
CREATE PROCEDURE DisplayPermissions
    @DatabaseName NVARCHAR(50)
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Xây dựng câu lệnh SQL để truy vấn trên cơ sở dữ liệu cụ thể 
    SET @SQL = '
               SELECT 
                   pr.name AS PrincipalName,
                   pr.type_desc AS PrincipalType,
                   dp.permission_name,
                   dp.state_desc AS PermissionState
               FROM ' + QUOTENAME(@DatabaseName) + '.sys.database_permissions dp
               JOIN ' + QUOTENAME(@DatabaseName) + '.sys.database_principals pr
                   ON dp.grantee_principal_id = pr.principal_id
               WHERE dp.class_desc = ''DATABASE'' OR dp.class_desc = ''SCHEMA'';';
    
    -- Thực thi câu lệnh SQL
    EXEC sp_executesql @SQL;
END;

-- Xem bảng quyền 
EXEC DisplayPermissions 
    @DatabaseName = 'YourDatabaseName';

-- 4. Sử dụng các thủ tục đã cập nhật
-- Tạo Login và User
EXEC CreateLoginAndUser 
    @DatabaseName = 'YourDatabaseName',
    @LoginName = 'M_Admin', 
    @Password = 'AdminPassword123!', 
    @UserName = 'M_Admin';

EXEC CreateLoginAndUser 
    @DatabaseName = 'YourDatabaseName',
    @LoginName = 'M_DEUser', 
    @Password = 'DEPassword123!', 
    @UserName = 'M_DEUser';

EXEC CreateLoginAndUser 
    @DatabaseName = 'YourDatabaseName',
    @LoginName = 'M_DAUser', 
    @Password = 'DAPassword123!', 
    @UserName = 'M_DAUser';

-- Phân quyền cho các vai trò
EXEC AssignRole_AD_DA
    @DatabaseName = 'YourDatabaseName', 
    @RoleType = 'Admin', 
    @UserName = 'M_Admin';

EXEC AssignRole_DE
    @DatabaseName = 'YourDatabaseName', 
    @RoleType = 'DE', 
    @UserName = 'M_DEUser';

EXEC AssignRole_AD_DA
    @DatabaseName = 'YourDatabaseName', 
    @RoleType = 'DA', 
    @UserName = 'M_DAUser';

-- Thủ tục thu hồi quyền
CREATE PROCEDURE dbo.RevokeAndDeleteUser
    @UserName NVARCHAR(50),
    @DatabaseName NVARCHAR(50)
AS
BEGIN
    BEGIN TRY
        DECLARE @SQL NVARCHAR(MAX);

        -- Tạo câu lệnh động để chọn cơ sở dữ liệu
        SET @SQL = 'USE ' + QUOTENAME(@DatabaseName) + ';';
        
        -- Thực thi câu lệnh USE để chuyển sang cơ sở dữ liệu mục tiêu
        EXEC sp_executesql @SQL;

        -- Thu hồi tất cả quyền trên cơ sở dữ liệu cho user
        SET @SQL = 'REVOKE ALL PRIVILEGES ON USER::' + QUOTENAME(@UserName) + ' TO ' + QUOTENAME(@UserName);
        EXEC sp_executesql @SQL;

        -- Xoá người dùng khỏi cơ sở dữ liệu
        SET @SQL = 'DROP USER ' + QUOTENAME(@UserName);
        EXEC sp_executesql @SQL;

        PRINT 'Người dùng ' + @UserName + ' đã bị thu hồi quyền và xoá khỏi cơ sở dữ liệu ' + @DatabaseName;
        
    END TRY
    BEGIN CATCH
        -- Xử lý lỗi nếu có
        PRINT 'Lỗi: ' + ERROR_MESSAGE();
    END CATCH
END;

EXEC dbo.RevokeAndDeleteUser @UserName = 'M_DEUser', 
                             @DatabaseName = 'IMDB_DB';



