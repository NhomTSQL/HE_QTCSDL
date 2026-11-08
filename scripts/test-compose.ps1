$ErrorActionPreference = "Stop"

$backupDirectory = Join-Path (Get-Location) "backups"
New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
$backupName = "compose-smoke-$([guid]::NewGuid().ToString('N')).bak"
$backupPath = "/var/opt/mssql/backups/$backupName"
$hostBackupPath = Join-Path $backupDirectory $backupName

try {
    $composeJson = docker compose config --format json
    if ($LASTEXITCODE -ne 0 -or -not $composeJson) {
        throw "Docker Compose configuration is invalid."
    }
    $composeConfig = $composeJson | ConvertFrom-Json
    $resolvedPassword = [string]$composeConfig.services.sqlserver.environment.MSSQL_SA_PASSWORD
    if (-not $resolvedPassword -or $resolvedPassword -match 'CHANGE_ME|ReplaceWithStrongPassword') {
        throw "Set a unique, strong MSSQL_SA_PASSWORD in .env before running this test."
    }
    $env:MSSQL_SA_PASSWORD = $resolvedPassword

    docker compose up -d --wait sqlserver
    if ($LASTEXITCODE -ne 0) {
        throw "SQL Server did not become healthy. Check Docker Desktop and docker compose logs."
    }

    $containerId = (docker compose ps -q sqlserver).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $containerId) {
        throw "Could not find the SQL Server container."
    }

    $memoryLimit = [long](docker inspect $containerId --format '{{.HostConfig.Memory}}')
    if ($LASTEXITCODE -ne 0 -or $memoryLimit -ne 4GB) {
        throw "Expected a 4 GiB Docker memory limit; found $memoryLimit bytes."
    }

    $containerEnvironment = docker inspect $containerId --format '{{json .Config.Env}}'
    if ($LASTEXITCODE -ne 0 -or -not $containerEnvironment) {
        throw "Could not inspect the SQL Server container environment."
    }
    if ($containerEnvironment -notmatch '"MSSQL_MEMORY_LIMIT_MB=3072"') {
        throw "Expected MSSQL_MEMORY_LIMIT_MB=3072 in the SQL Server container."
    }

    $sql = @"
IF NOT EXISTS (
    SELECT 1
    FROM sys.dm_server_services
    WHERE servicename LIKE N'%Agent%'
      AND status_desc = N'Running'
)
    THROW 51000, 'SQL Server Agent is not running', 1;

IF (SELECT CONVERT(INT, physical_memory_kb / 1024)
    FROM sys.dm_os_sys_info) > 3072
    THROW 51001, 'SQL Server memory visibility exceeds 3072 MB', 1;

BACKUP DATABASE [master]
TO DISK = N'$backupPath'
WITH INIT, CHECKSUM;

RESTORE VERIFYONLY
FROM DISK = N'$backupPath'
WITH CHECKSUM;
"@

    docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd `
        -C -S localhost -U sa -P $env:MSSQL_SA_PASSWORD -b -Q $sql
    if ($LASTEXITCODE -ne 0) {
        throw "SQL Agent check or backup verification failed."
    }

    if (-not (Test-Path -LiteralPath $hostBackupPath)) {
        throw "Backup file was not visible in the host backups directory; verify the bind mount."
    }

    Write-Output "PASS: SQL Server Agent is running."
    Write-Output "PASS: SQL Server memory is limited to 3072 MB inside a 4 GiB container."
    Write-Output "PASS: SQL backup was created, verified, and visible in backups/."
}
finally {
    if (Test-Path -LiteralPath $hostBackupPath) {
        Remove-Item -LiteralPath $hostBackupPath -Force
    }
}
