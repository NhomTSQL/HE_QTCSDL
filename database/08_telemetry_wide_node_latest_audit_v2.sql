-- ============================================================================
-- AR-IMMS: Wide telemetry snapshots, node latest projection and audit v2
-- Chạy sau database/01-07. Script có thể chạy lại an toàn.
-- ============================================================================

USE AR_IMMS;
GO

IF OBJECT_ID(N'dbo.telemetry_wide', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.telemetry_wide (
        telemetry_id            BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_telemetry_wide PRIMARY KEY,
        node_id                 INT NOT NULL,
        collected_at            DATETIME2(0) NOT NULL
            CONSTRAINT DF_telemetry_wide_collected_at DEFAULT CONVERT(DATETIME2(0), SYSUTCDATETIME()),
        cpu_usage_percent       DECIMAL(5,2) NULL,
        memory_usage_percent    DECIMAL(5,2) NULL,
        disk_usage_percent      DECIMAL(5,2) NULL,
        temperature_celsius     DECIMAL(6,2) NULL,
        network_in_bytes        BIGINT NULL,
        network_out_bytes       BIGINT NULL,
        uptime_seconds          BIGINT NULL,
        process_count           INT NULL,
        CONSTRAINT FK_telemetry_wide_node FOREIGN KEY (node_id)
            REFERENCES dbo.nodes(id) ON DELETE CASCADE,
        CONSTRAINT CK_telemetry_wide_cpu CHECK (cpu_usage_percent IS NULL OR cpu_usage_percent BETWEEN 0 AND 100),
        CONSTRAINT CK_telemetry_wide_memory CHECK (memory_usage_percent IS NULL OR memory_usage_percent BETWEEN 0 AND 100),
        CONSTRAINT CK_telemetry_wide_disk CHECK (disk_usage_percent IS NULL OR disk_usage_percent BETWEEN 0 AND 100),
        CONSTRAINT CK_telemetry_wide_network_in CHECK (network_in_bytes IS NULL OR network_in_bytes >= 0),
        CONSTRAINT CK_telemetry_wide_network_out CHECK (network_out_bytes IS NULL OR network_out_bytes >= 0),
        CONSTRAINT CK_telemetry_wide_uptime CHECK (uptime_seconds IS NULL OR uptime_seconds >= 0),
        CONSTRAINT CK_telemetry_wide_processes CHECK (process_count IS NULL OR process_count >= 0),
        CONSTRAINT UQ_telemetry_wide_node_collected UNIQUE (node_id, collected_at)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_telemetry_wide_node_collected'
      AND object_id = OBJECT_ID(N'dbo.telemetry_wide')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_telemetry_wide_node_collected
        ON dbo.telemetry_wide(node_id, collected_at DESC)
        INCLUDE (cpu_usage_percent, memory_usage_percent, temperature_celsius);
END;
GO

IF OBJECT_ID(N'dbo.node_latest', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.node_latest (
        node_id                 INT NOT NULL
            CONSTRAINT PK_node_latest PRIMARY KEY,
        telemetry_id            BIGINT NOT NULL,
        collected_at            DATETIME2(0) NOT NULL,
        cpu_usage_percent       DECIMAL(5,2) NULL,
        memory_usage_percent    DECIMAL(5,2) NULL,
        disk_usage_percent      DECIMAL(5,2) NULL,
        temperature_celsius     DECIMAL(6,2) NULL,
        network_in_bytes        BIGINT NULL,
        network_out_bytes       BIGINT NULL,
        uptime_seconds          BIGINT NULL,
        process_count           INT NULL,
        CONSTRAINT FK_node_latest_node FOREIGN KEY (node_id)
            REFERENCES dbo.nodes(id) ON DELETE CASCADE,
        CONSTRAINT FK_node_latest_telemetry FOREIGN KEY (telemetry_id)
            REFERENCES dbo.telemetry_wide(telemetry_id)
    );
END;
GO

IF COL_LENGTH(N'dbo.audit_logs', N'event_id') IS NULL
    ALTER TABLE dbo.audit_logs ADD event_id UNIQUEIDENTIFIER NULL;
IF COL_LENGTH(N'dbo.audit_logs', N'event_type') IS NULL
    ALTER TABLE dbo.audit_logs ADD event_type NVARCHAR(100) NULL;
IF COL_LENGTH(N'dbo.audit_logs', N'correlation_id') IS NULL
    ALTER TABLE dbo.audit_logs ADD correlation_id UNIQUEIDENTIFIER NULL;
IF COL_LENGTH(N'dbo.audit_logs', N'created_at') IS NULL
    ALTER TABLE dbo.audit_logs ADD created_at DATETIME2(0) NULL;
GO

UPDATE dbo.audit_logs
SET event_id = ISNULL(event_id, NEWID()),
    event_type = ISNULL(event_type, action),
    created_at = ISNULL(created_at, CONVERT(DATETIME2(0), [timestamp]))
WHERE event_id IS NULL OR event_type IS NULL OR created_at IS NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.audit_logs')
      AND name = N'DF_audit_logs_event_id'
)
    ALTER TABLE dbo.audit_logs ADD CONSTRAINT DF_audit_logs_event_id
        DEFAULT NEWSEQUENTIALID() FOR event_id;
IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.audit_logs')
      AND name = N'DF_audit_logs_event_type'
)
    ALTER TABLE dbo.audit_logs ADD CONSTRAINT DF_audit_logs_event_type
        DEFAULT N'UNSPECIFIED' FOR event_type;
IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.audit_logs')
      AND name = N'DF_audit_logs_created_at'
)
    ALTER TABLE dbo.audit_logs ADD CONSTRAINT DF_audit_logs_created_at
        DEFAULT CONVERT(DATETIME2(0), SYSUTCDATETIME()) FOR created_at;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_audit_logs_event_id'
      AND object_id = OBJECT_ID(N'dbo.audit_logs')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_audit_logs_event_id
        ON dbo.audit_logs(event_id);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_record_telemetry_wide
    @node_id INT,
    @collected_at DATETIME2(0),
    @cpu_usage_percent DECIMAL(5,2) = NULL,
    @memory_usage_percent DECIMAL(5,2) = NULL,
    @disk_usage_percent DECIMAL(5,2) = NULL,
    @temperature_celsius DECIMAL(6,2) = NULL,
    @network_in_bytes BIGINT = NULL,
    @network_out_bytes BIGINT = NULL,
    @uptime_seconds BIGINT = NULL,
    @process_count INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.nodes WHERE id = @node_id)
        THROW 51050, N'Unknown node.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.telemetry_wide (
            node_id, collected_at, cpu_usage_percent, memory_usage_percent,
            disk_usage_percent, temperature_celsius, network_in_bytes,
            network_out_bytes, uptime_seconds, process_count
        )
        VALUES (
            @node_id, @collected_at, @cpu_usage_percent, @memory_usage_percent,
            @disk_usage_percent, @temperature_celsius, @network_in_bytes,
            @network_out_bytes, @uptime_seconds, @process_count
        );

        DECLARE @telemetry_id BIGINT = CONVERT(BIGINT, SCOPE_IDENTITY());

        MERGE dbo.node_latest AS target
        USING (
            SELECT telemetry_id, node_id, collected_at, cpu_usage_percent,
                   memory_usage_percent, disk_usage_percent, temperature_celsius,
                   network_in_bytes, network_out_bytes, uptime_seconds, process_count
            FROM dbo.telemetry_wide
            WHERE telemetry_id = @telemetry_id
        ) AS source
        ON target.node_id = source.node_id
        WHEN MATCHED AND source.collected_at >= target.collected_at THEN
            UPDATE SET telemetry_id = source.telemetry_id,
                       collected_at = source.collected_at,
                       cpu_usage_percent = source.cpu_usage_percent,
                       memory_usage_percent = source.memory_usage_percent,
                       disk_usage_percent = source.disk_usage_percent,
                       temperature_celsius = source.temperature_celsius,
                       network_in_bytes = source.network_in_bytes,
                       network_out_bytes = source.network_out_bytes,
                       uptime_seconds = source.uptime_seconds,
                       process_count = source.process_count
        WHEN NOT MATCHED THEN
            INSERT (node_id, telemetry_id, collected_at, cpu_usage_percent,
                    memory_usage_percent, disk_usage_percent, temperature_celsius,
                    network_in_bytes, network_out_bytes, uptime_seconds, process_count)
            VALUES (source.node_id, source.telemetry_id, source.collected_at,
                    source.cpu_usage_percent, source.memory_usage_percent,
                    source.disk_usage_percent, source.temperature_celsius,
                    source.network_in_bytes, source.network_out_bytes,
                    source.uptime_seconds, source.process_count);

        INSERT INTO dbo.audit_logs (
            user_id, username, action, target_entity, target_id, details_json,
            ip_address, event_type, correlation_id
        )
        VALUES (
            NULL, N'SYSTEM', N'TELEMETRY_WIDE_RECORDED', N'NODE',
            CONVERT(NVARCHAR(50), @node_id),
            N'{"telemetry_id":' + CONVERT(NVARCHAR(30), @telemetry_id) + N'}',
            NULL, N'TELEMETRY_WIDE_RECORDED', NEWID()
        );

        COMMIT TRANSACTION;
        SELECT @telemetry_id AS telemetry_id;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

PRINT N'=== Wide telemetry, node_latest and audit_logs v2 ready ===';
GO
