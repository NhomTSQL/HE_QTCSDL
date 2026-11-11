param(
    [string]$Url = "http://localhost:5000/health"
)

$ErrorActionPreference = "Stop"

try {
    $response = Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 10
    if ($response.status -ne "healthy" -or $response.database -ne "connected") {
        throw "Unexpected health response: status='$($response.status)', database='$($response.database)'"
    }

    Write-Output "PASS: $Url returned status=healthy and database=connected"
}
catch {
    Write-Error "FAIL: $Url did not return a healthy database response. $($_.Exception.Message)"
    exit 1
}
