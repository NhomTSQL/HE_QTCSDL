-- Run AFTER 25_password_recovery.sql. Re-runnable; no data reset.
USE AR_IMMS;
GO

CREATE OR ALTER PROCEDURE dbo.usp_authenticate_user @username NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.id AS user_id,u.username,u.email,u.password_hash,u.full_name,
           u.role_id,r.name AS role_name,u.security_version,u.mfa_enabled,u.mfa_secret_encrypted
    FROM dbo.users u JOIN dbo.roles r ON r.id=u.role_id
    WHERE u.username=@username AND u.is_active=1;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_users_revoke_changed_credentials ON dbo.users AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF ROWCOUNT_BIG() = 0 RETURN;
    IF TRIGGER_NESTLEVEL(OBJECT_ID(N'dbo.trg_users_revoke_changed_credentials')) > 1 RETURN;
    IF NOT EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.id = i.id
        WHERE i.security_version = d.security_version AND (
            i.role_id <> d.role_id OR i.is_active <> d.is_active
            OR i.username <> d.username
            OR CONVERT(VARBINARY(510), i.password_hash) <> CONVERT(VARBINARY(510), d.password_hash)
        )
    ) RETURN;
    UPDATE u SET security_version=u.security_version+1
    FROM dbo.users u JOIN inserted i ON i.id=u.id JOIN deleted d ON d.id=u.id
    WHERE i.security_version=d.security_version AND (
        i.role_id<>d.role_id OR i.is_active<>d.is_active
        OR i.username<>d.username
        OR CONVERT(VARBINARY(510),i.password_hash)<>CONVERT(VARBINARY(510),d.password_hash)
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_validate_auth_session
    @jti CHAR(36), @user_id INT, @security_version INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (1) u.id AS user_id, u.username, r.name AS role_name,
           u.is_active, u.security_version, s.expires_at
    FROM dbo.auth_sessions s
    JOIN dbo.users u ON u.id=s.user_id
    JOIN dbo.roles r ON r.id=u.role_id
    WHERE s.jti=@jti AND s.user_id=@user_id AND s.revoked_at IS NULL
      AND s.expires_at>SYSUTCDATETIME() AND u.is_active=1
      AND u.security_version=@security_version;
END;
GO

-- Field technicians may read shared inventory, but may mutate only assigned work.
-- Locks live in the caller's transaction through the following write.
CREATE OR ALTER PROCEDURE dbo.usp_authorize_ticket_write
    @ticket_id INT, @actor_user_id INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @role NVARCHAR(50) = (
        SELECT r.name FROM dbo.users u JOIN dbo.roles r ON r.id=u.role_id
        WHERE u.id=@actor_user_id AND u.is_active=1
    );
    IF @role IN (N'ADMINISTRATOR',N'SYSTEM_OPERATOR') RETURN;
    IF @role=N'FIELD_TECHNICIAN' AND EXISTS (
        SELECT 1 FROM dbo.tickets WITH (UPDLOCK,HOLDLOCK)
        WHERE id=@ticket_id AND assigned_to_user_id=@actor_user_id AND status<>N'CLOSED'
    ) RETURN;
    THROW 51130, 'This operation requires an assigned ticket.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_authorize_container_restart
    @container_id INT, @actor_user_id INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @role NVARCHAR(50) = (
        SELECT r.name FROM dbo.users u JOIN dbo.roles r ON r.id=u.role_id
        WHERE u.id=@actor_user_id AND u.is_active=1
    );
    IF @role IN (N'ADMINISTRATOR',N'SYSTEM_OPERATOR') RETURN;
    IF @role=N'FIELD_TECHNICIAN' AND EXISTS (
        SELECT 1 FROM dbo.containers c
        JOIN dbo.tickets t WITH (UPDLOCK,HOLDLOCK) ON t.node_id=c.node_id
        WHERE c.id=@container_id AND t.assigned_to_user_id=@actor_user_id
          AND t.status IN (N'OPEN',N'IN_PROGRESS')
    ) RETURN;
    THROW 51130, 'This operation requires an assigned ticket.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_get_own_mfa_state @user_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT mfa_setup_secret_encrypted,mfa_secret_encrypted,mfa_enabled
    FROM dbo.users WHERE id=@user_id AND is_active=1;
END;
GO

-- A bearer session alone must not overwrite already-enabled MFA.
CREATE OR ALTER PROCEDURE dbo.usp_begin_mfa_setup @user_id INT, @encrypted_secret VARBINARY(512)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.users SET mfa_setup_secret_encrypted=@encrypted_secret
    WHERE id=@user_id AND is_active=1 AND mfa_enabled=0
      AND role_id=(SELECT id FROM dbo.roles WHERE name=N'ADMINISTRATOR');
    IF @@ROWCOUNT=0 THROW 51121, 'Account not eligible for MFA setup.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_upsert_node_host_specs
    @node_id            INT,
    @ip_address         NVARCHAR(50) = NULL,
    @mac_address        NVARCHAR(50) = NULL,
    @cpu_model          NVARCHAR(100),
    @cpu_cores          INT,
    @total_ram_gb       FLOAT,
    @total_storage_gb   FLOAT,
    @os_name            NVARCHAR(100),
    @os_version         NVARCHAR(50),
    @nics_json          NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51062, N'Node not found.', 1;

    BEGIN TRANSACTION;

    UPDATE dbo.nodes
    SET ip_address = COALESCE(NULLIF(@ip_address, N''), ip_address),
        mac_address = COALESCE(NULLIF(@mac_address, N''), mac_address),
        last_ping_at = SYSUTCDATETIME(),
        updated_at = SYSUTCDATETIME()
    WHERE id = @node_id;

    DECLARE @asset_spec_id INT;
    SELECT @asset_spec_id = id FROM dbo.asset_specs WHERE node_id = @node_id;

    IF @asset_spec_id IS NOT NULL
    BEGIN
        UPDATE dbo.asset_specs
        SET cpu_model = @cpu_model,
            cpu_cores = @cpu_cores,
            total_ram_gb = @total_ram_gb,
            total_storage_gb = @total_storage_gb,
            os_name = @os_name,
            os_version = @os_version,
            updated_at = SYSUTCDATETIME()
        WHERE id = @asset_spec_id;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.asset_specs (node_id, cpu_model, cpu_cores, total_ram_gb, total_storage_gb, os_name, os_version)
        VALUES (@node_id, @cpu_model, @cpu_cores, @total_ram_gb, @total_storage_gb, @os_name, @os_version);
        SET @asset_spec_id = CONVERT(INT, SCOPE_IDENTITY());
    END;

    IF @nics_json IS NOT NULL AND ISJSON(@nics_json) = 1
    BEGIN
        DELETE FROM dbo.asset_network_interfaces WHERE asset_spec_id = @asset_spec_id;
        INSERT INTO dbo.asset_network_interfaces (asset_spec_id, interface_name, mac_address, ipv4_address, speed_mbps, is_up)
        SELECT @asset_spec_id,
               LEFT(LTRIM(RTRIM(j.interface_name)), 100),
               NULLIF(LEFT(LTRIM(RTRIM(j.mac_address)), 50), N''),
               NULLIF(LEFT(LTRIM(RTRIM(j.ipv4_address)), 50), N''),
               j.speed_mbps,
               j.is_up
        FROM OPENJSON(@nics_json)
        WITH (
            interface_name NVARCHAR(100) N'$.interface_name',
            mac_address    NVARCHAR(50)  N'$.mac_address',
            ipv4_address   NVARCHAR(50)  N'$.ipv4_address',
            speed_mbps     INT           N'$.speed_mbps',
            is_up          BIT           N'$.is_up'
        ) j
        WHERE NULLIF(LTRIM(RTRIM(j.interface_name)), N'') IS NOT NULL;
    END;

    COMMIT TRANSACTION;
    SELECT @node_id AS node_id, @asset_spec_id AS asset_spec_id;
END;
GO
