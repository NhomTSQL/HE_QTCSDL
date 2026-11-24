USE AR_IMMS;
GO

IF OBJECT_ID(N'dbo.account_access_requests', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.account_access_requests (
        id INT IDENTITY(1,1) PRIMARY KEY,
        username NVARCHAR(50) NOT NULL,
        email NVARCHAR(100) NOT NULL,
        full_name NVARCHAR(100) NOT NULL,
        requested_role NVARCHAR(50) NOT NULL,
        note NVARCHAR(500) NULL,
        source_ip_hash CHAR(64) NOT NULL,
        status NVARCHAR(20) NOT NULL DEFAULT N'PENDING',
        reviewed_by_user_id INT NULL,
        reviewed_at DATETIME2 NULL,
        created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_account_access_request_status CHECK (status IN (N'PENDING', N'APPROVED', N'REJECTED')),
        CONSTRAINT FK_account_access_request_reviewer FOREIGN KEY (reviewed_by_user_id) REFERENCES dbo.users(id)
    );
END;
GO

IF OBJECT_ID(N'dbo.auth_sessions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.auth_sessions (
        jti CHAR(36) NOT NULL PRIMARY KEY,
        user_id INT NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
        issued_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        expires_at DATETIME2 NOT NULL,
        revoked_at DATETIME2 NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.password_recovery_codes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.password_recovery_codes (user_id INT NOT NULL PRIMARY KEY REFERENCES dbo.users(id) ON DELETE CASCADE, code_hash CHAR(64) NOT NULL UNIQUE, password_fingerprint BINARY(32) NOT NULL, expires_at DATETIME2 NOT NULL);
END;
GO

IF OBJECT_ID(N'dbo.mfa_backup_codes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.mfa_backup_codes (user_id INT NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE, code_hash CHAR(64) NOT NULL, created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(), used_at DATETIME2 NULL, CONSTRAINT PK_mfa_backup_codes PRIMARY KEY (user_id, code_hash));
END;
GO

IF COL_LENGTH(N'dbo.users', N'security_version') IS NULL ALTER TABLE dbo.users ADD security_version INT NOT NULL CONSTRAINT DF_users_security_version DEFAULT (1);
IF COL_LENGTH(N'dbo.users', N'mfa_secret_encrypted') IS NULL ALTER TABLE dbo.users ADD mfa_secret_encrypted VARBINARY(512) NULL;
IF COL_LENGTH(N'dbo.users', N'mfa_setup_secret_encrypted') IS NULL ALTER TABLE dbo.users ADD mfa_setup_secret_encrypted VARBINARY(512) NULL;
IF COL_LENGTH(N'dbo.users', N'mfa_enabled') IS NULL ALTER TABLE dbo.users ADD mfa_enabled BIT NOT NULL CONSTRAINT DF_users_mfa_enabled DEFAULT (0);
GO

CREATE OR ALTER PROCEDURE dbo.usp_begin_mfa_setup @user_id INT, @encrypted_secret VARBINARY(512)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.users SET mfa_setup_secret_encrypted=@encrypted_secret WHERE id=@user_id AND is_active=1 AND role_id=(SELECT id FROM dbo.roles WHERE name=N'ADMINISTRATOR');
    IF @@ROWCOUNT=0 THROW 51121, 'Administrator account not found.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_enable_mfa @user_id INT, @backup_hashes NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    UPDATE dbo.users SET mfa_secret_encrypted=mfa_setup_secret_encrypted,mfa_setup_secret_encrypted=NULL,mfa_enabled=1,security_version=security_version+1
    WHERE id=@user_id AND is_active=1 AND role_id=(SELECT id FROM dbo.roles WHERE name=N'ADMINISTRATOR') AND mfa_setup_secret_encrypted IS NOT NULL;
    IF @@ROWCOUNT=0 THROW 51122, 'No pending authenticator setup exists.', 1;
    DELETE FROM dbo.mfa_backup_codes WHERE user_id=@user_id;
    INSERT INTO dbo.mfa_backup_codes(user_id,code_hash)
    SELECT @user_id, [value] FROM OPENJSON(@backup_hashes) WHERE LEN([value])=64;
    IF @@ROWCOUNT<>10 THROW 51123, 'Exactly ten recovery codes are required.', 1;
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_disable_mfa @user_id INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.users SET mfa_enabled=0,mfa_secret_encrypted=NULL,mfa_setup_secret_encrypted=NULL,security_version=security_version+1 WHERE id=@user_id AND is_active=1;
    DELETE FROM dbo.mfa_backup_codes WHERE user_id=@user_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_use_mfa_backup_code @user_id INT, @code_hash CHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    UPDATE dbo.mfa_backup_codes WITH (UPDLOCK, ROWLOCK) SET used_at=SYSUTCDATETIME() WHERE user_id=@user_id AND code_hash=@code_hash AND used_at IS NULL;
    DECLARE @used BIT=CASE WHEN @@ROWCOUNT=1 THEN 1 ELSE 0 END;
    COMMIT TRANSACTION;
    SELECT @used AS used;
END;
GO

IF OBJECT_ID(N'dbo.shift_handover_notes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.shift_handover_notes (id BIGINT IDENTITY(1,1) PRIMARY KEY, user_id INT NOT NULL REFERENCES dbo.users(id), username NVARCHAR(50) NOT NULL, note NVARCHAR(1000) NOT NULL, created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_request_account_access
    @username NVARCHAR(50), @email NVARCHAR(100), @full_name NVARCHAR(100),
    @requested_role NVARCHAR(50), @note NVARCHAR(500) = NULL, @source_ip_hash CHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    IF @requested_role NOT IN (N'FIELD_TECHNICIAN', N'SYSTEM_OPERATOR')
        THROW 51110, 'Invalid requested role.', 1;
    IF (SELECT COUNT(*) FROM dbo.account_access_requests WHERE source_ip_hash = @source_ip_hash AND created_at > DATEADD(MINUTE, -15, SYSUTCDATETIME())) >= 5
        THROW 51112, 'Request limit reached.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE username = @username OR email = @email)
       AND NOT EXISTS (SELECT 1 FROM dbo.account_access_requests WHERE email = @email AND status = N'PENDING')
    BEGIN
        INSERT INTO dbo.account_access_requests (username, email, full_name, requested_role, note, source_ip_hash)
        VALUES (@username, @email, @full_name, @requested_role, NULLIF(@note, N''), @source_ip_hash);
    END;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_account_access_requests
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, username, email, full_name, requested_role, note, created_at
    FROM dbo.account_access_requests WHERE status = N'PENDING'
    ORDER BY created_at, id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_list_auth_sessions @user_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT jti,issued_at,expires_at FROM dbo.auth_sessions WHERE user_id=@user_id AND revoked_at IS NULL AND expires_at>SYSUTCDATETIME() ORDER BY issued_at DESC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_revoke_other_auth_sessions @user_id INT,@current_jti CHAR(36)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.auth_sessions SET revoked_at=SYSUTCDATETIME() WHERE user_id=@user_id AND jti<>@current_jti AND revoked_at IS NULL;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_add_handover_note @user_id INT,@username NVARCHAR(50),@note NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.shift_handover_notes(user_id,username,note) VALUES(@user_id,@username,@note);
    SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS id;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_list_handover_notes
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (50) id,username,note,created_at FROM dbo.shift_handover_notes ORDER BY created_at DESC,id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_change_own_password
    @user_id INT, @new_password_hash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    UPDATE dbo.users SET password_hash = @new_password_hash, security_version = security_version + 1,
        updated_at = SYSUTCDATETIME() WHERE id = @user_id;
    UPDATE dbo.auth_sessions SET revoked_at = SYSUTCDATETIME() WHERE user_id = @user_id AND revoked_at IS NULL;
    INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, timestamp)
    SELECT id, username, N'PASSWORD_CHANGED', N'USER', CONVERT(NVARCHAR(50), id), SYSUTCDATETIME()
    FROM dbo.users WHERE id = @user_id;
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_review_account_access_request
    @request_id INT, @actor_user_id INT, @decision NVARCHAR(10),
    @role_name NVARCHAR(50) = NULL, @bootstrap_hash NVARCHAR(255) = NULL, @code_hash CHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    DECLARE @actor NVARCHAR(50) = (SELECT u.username FROM dbo.users u JOIN dbo.roles r ON r.id=u.role_id WHERE u.id=@actor_user_id AND u.is_active=1 AND r.name=N'ADMINISTRATOR');
    IF @actor IS NULL THROW 51100, 'Administrator access required.', 1;
    DECLARE @username NVARCHAR(50), @email NVARCHAR(100), @full_name NVARCHAR(100), @requested_role NVARCHAR(50), @user_id INT;
    SELECT @username=username, @email=email, @full_name=full_name, @requested_role=requested_role
    FROM dbo.account_access_requests WITH (UPDLOCK, HOLDLOCK) WHERE id=@request_id AND status=N'PENDING';
    IF @username IS NULL THROW 51114, 'Pending request not found.', 1;
    IF @decision = N'REJECT'
    BEGIN
        UPDATE dbo.account_access_requests SET status=N'REJECTED', reviewed_by_user_id=@actor_user_id, reviewed_at=SYSUTCDATETIME() WHERE id=@request_id;
    END
    ELSE IF @decision = N'APPROVE'
    BEGIN
        IF @role_name NOT IN (N'FIELD_TECHNICIAN', N'SYSTEM_OPERATOR') OR @role_name <> @requested_role
            THROW 51115, 'Requested role does not match.', 1;
        IF @bootstrap_hash IS NULL OR @code_hash IS NULL THROW 51116, 'Bootstrap credentials are required.', 1;
        IF EXISTS (SELECT 1 FROM dbo.users WHERE username=@username OR email=@email)
            THROW 51117, 'Account details conflict.', 1;
        INSERT INTO dbo.users (username,email,password_hash,full_name,role_id,is_active)
        VALUES (@username,@email,@bootstrap_hash,@full_name,(SELECT id FROM dbo.roles WHERE name=@role_name),1);
        SET @user_id=CONVERT(INT,SCOPE_IDENTITY());
        INSERT INTO dbo.password_recovery_codes (user_id,code_hash,password_fingerprint,expires_at)
        SELECT @user_id,@code_hash,HASHBYTES('SHA2_256',password_hash),DATEADD(HOUR,24,SYSUTCDATETIME()) FROM dbo.users WHERE id=@user_id;
        UPDATE dbo.account_access_requests SET status=N'APPROVED', reviewed_by_user_id=@actor_user_id, reviewed_at=SYSUTCDATETIME() WHERE id=@request_id;
        INSERT INTO dbo.audit_logs (user_id,username,action,target_entity,target_id,details_json,timestamp)
        VALUES (@actor_user_id,@actor,N'ACCOUNT_ACCESS_APPROVED',N'USER',CONVERT(NVARCHAR(50),@user_id),
            N'{"role":"' + @role_name + N'"}',SYSUTCDATETIME());
    END
    ELSE THROW 51118, 'Invalid decision.', 1;
    COMMIT TRANSACTION;
    SELECT @user_id AS user_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_issue_password_recovery
    @user_id INT,
    @actor_user_id INT,
    @code_hash CHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @actor_name NVARCHAR(50) = (
        SELECT u.username FROM dbo.users u JOIN dbo.roles r ON u.role_id = r.id
        WHERE u.id = @actor_user_id AND u.is_active = 1 AND r.name = N'ADMINISTRATOR'
    );
    IF @actor_name IS NULL THROW 51100, 'Administrator access required.', 1;

    DECLARE @fingerprint BINARY(32) = (
        SELECT HASHBYTES('SHA2_256', password_hash)
        FROM dbo.users WITH (UPDLOCK, HOLDLOCK) WHERE id = @user_id AND is_active = 1
    );
    IF @fingerprint IS NULL THROW 51101, 'Active account not found.', 1;

    DELETE FROM dbo.password_recovery_codes WHERE user_id = @user_id;
    INSERT INTO dbo.password_recovery_codes (user_id, code_hash, password_fingerprint, expires_at)
    VALUES (@user_id, @code_hash, @fingerprint, DATEADD(MINUTE, 15, SYSUTCDATETIME()));

    INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, timestamp)
    VALUES (@actor_user_id, @actor_name, N'PASSWORD_RECOVERY_ISSUED', N'USER', CONVERT(NVARCHAR(50), @user_id), SYSUTCDATETIME());

    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_redeem_password_recovery
    @code_hash CHAR(64),
    @password_hash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @user_id INT = (SELECT user_id FROM dbo.password_recovery_codes WHERE code_hash = @code_hash);
    IF @user_id IS NULL THROW 51102, 'Invalid or expired recovery code.', 1;

    BEGIN TRANSACTION;

    DECLARE @username NVARCHAR(50);
    DECLARE @fingerprint BINARY(32);
    SELECT @username = username, @fingerprint = HASHBYTES('SHA2_256', password_hash)
    FROM dbo.users WITH (UPDLOCK, HOLDLOCK) WHERE id = @user_id AND is_active = 1;

    DELETE FROM dbo.password_recovery_codes
    WHERE user_id = @user_id AND code_hash = @code_hash
      AND password_fingerprint = @fingerprint AND expires_at > SYSUTCDATETIME();
    IF @@ROWCOUNT = 0 THROW 51102, 'Invalid or expired recovery code.', 1;

    UPDATE dbo.users SET password_hash = @password_hash, security_version = security_version + 1, updated_at = SYSUTCDATETIME() WHERE id = @user_id;
    UPDATE dbo.auth_sessions SET revoked_at = SYSUTCDATETIME() WHERE user_id = @user_id AND revoked_at IS NULL;

    INSERT INTO dbo.audit_logs (user_id, username, action, target_entity, target_id, timestamp)
    VALUES (@user_id, @username, N'PASSWORD_RECOVERED', N'USER', CONVERT(NVARCHAR(50), @user_id), SYSUTCDATETIME());

    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_create_auth_session
    @jti CHAR(36), @user_id INT, @expires_at DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.auth_sessions(jti,user_id,expires_at)
    SELECT @jti,@user_id,@expires_at FROM dbo.users WHERE id=@user_id AND is_active=1;
    IF @@ROWCOUNT=0 THROW 51120, 'Active account not found.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_validate_auth_session @jti CHAR(36), @user_id INT, @security_version INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (1) u.id AS user_id, u.username, u.is_active, u.security_version, s.expires_at
    FROM dbo.auth_sessions s JOIN dbo.users u ON u.id=s.user_id
    WHERE s.jti=@jti AND s.user_id=@user_id AND s.revoked_at IS NULL
      AND s.expires_at > SYSUTCDATETIME() AND u.is_active=1 AND u.security_version=@security_version;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_revoke_auth_session @jti CHAR(36), @user_id INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.auth_sessions SET revoked_at=SYSUTCDATETIME() WHERE jti=@jti AND user_id=@user_id AND revoked_at IS NULL;
END;
GO
