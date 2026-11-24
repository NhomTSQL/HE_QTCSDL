[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Database = 'AR_IMMS',

    [Parameter(Mandatory = $false)]
    [string]$Server = 'localhost,1433',

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Canonical install order from database/README.md. Reset/test/benchmark/restore scripts
# are intentionally excluded and must never run here.
$ScriptOrder = @(
    '01_create_database.sql',
    '02_create_tables.sql',
    '03_seed_data.sql',
    '04_procedures_triggers_views.sql',
    '05_retention_policy.sql',
    '08_dev_node_api_key.sql',
    '09_auth_procedures.sql',
    '10_agent_job_heartbeat.sql',
    '12_backup_recovery_model.sql',
    '13_backup_jobs.sql',
    '14_backup_cleanup.sql',
    '16_alert_dedupe.sql',
    '17_dashboard_api_procedures.sql',
    '19_security_and_core_fixes.sql',
    '20_extended_features_procedures.sql',
    '22_scale_architecture.sql',
    '23_least_privilege_login.sql',
    '25_password_recovery.sql',
    '26_security_hardening.sql'
)

$ScriptRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\database\canonical')).Path
$Errors = @()

if ($DryRun) {
    Write-Host 'DRY RUN - scripts that would execute:' -ForegroundColor Cyan
    foreach ($file in $ScriptOrder) {
        Write-Host ("  {0}" -f (Join-Path $ScriptRoot $file))
    }
    return
}

foreach ($file in $ScriptOrder) {
    $path = Join-Path $ScriptRoot $file

    if (!(Test-Path $path)) {
        Write-Error "Missing script: $path"
        exit 1
    }

    Write-Host ("[RUN] {0}" -f $file) -ForegroundColor Green

    # The first script creates the database, so it must connect to master.
    $targetDatabase = if ($file -eq '01_create_database.sql') { 'master' } else { $Database }

    if ($Credential) {
        $previousSqlcmdPassword = $env:SQLCMDPASSWORD
        try {
            $env:SQLCMDPASSWORD = $Credential.GetNetworkCredential().Password
            & sqlcmd -S $Server -d $targetDatabase -U $Credential.UserName -i "$path" -b
        }
        finally {
            if ($null -eq $previousSqlcmdPassword) {
                Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue
            }
            else {
                $env:SQLCMDPASSWORD = $previousSqlcmdPassword
            }
        }
    }
    else {
        & sqlcmd -S $Server -d $targetDatabase -E -i "$path" -b
    }

    if ($LASTEXITCODE -ne 0) {
        $Errors += $file
        Write-Error "FAILED: $file"
        break
    }
}

if ($Errors.Count -gt 0) {
    Write-Host "Setup aborted after $($Errors.Count) failure(s): $($Errors -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host 'SQL Server canonical setup completed successfully.' -ForegroundColor Green

