Set-StrictMode -Version Latest

function Invoke-AuditApi {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('GET','POST')][string]$Method,
        [Parameter(Mandatory=$true)][string]$Path,
        [object]$Body
    )

    $uri = ($ApiBaseUrl.TrimEnd('/') + '/' + $Path.TrimStart('/'))
    $headers = @{ Accept = 'application/json' }
    $json = $null
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 30 -Compress
    }

    try {
        $params = @{
            Uri = $uri
            Method = $Method
            Headers = $headers
            TimeoutSec = $ApiTimeoutSec
            UseBasicParsing = $true
            ErrorAction = 'Stop'
        }
        if ($null -ne $json) {
            $params.Body = $json
            $params.ContentType = 'application/json; charset=utf-8'
        }
        return Invoke-RestMethod @params
    }
    catch {
        throw "API request failed: $Method $uri`n$($_.Exception.Message)"
    }
}

function Test-AuditCode {
    param([Parameter(Mandatory=$true)][string]$Code)
    return Invoke-AuditApi -Method POST -Path 'pc-audit/validate-code' -Body @{ code = $Code }
}

function Submit-Audit {
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Department,
        [Parameter(Mandatory=$true)][string]$EmployeeName,
        [Parameter(Mandatory=$true)][hashtable]$Data
    )
    return Invoke-AuditApi -Method POST -Path 'pc-audit/submit' -Body @{
        code = $Code
        department = $Department
        employee_name = $EmployeeName
        data = $Data
    }
}
