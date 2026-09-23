Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Config.ps1"
. "$PSScriptRoot\ApiClient.ps1"
. "$PSScriptRoot\Collector.ps1"

function Read-Required($Prompt) {
    do { $value = Read-Host $Prompt } while ([string]::IsNullOrWhiteSpace($value))
    return $value.Trim()
}

Clear-Host
Write-Host '========================================='
Write-Host '          MSTAR PC AUDIT TOOL'
Write-Host '========================================='
Write-Host ''

$code = Read-Required 'Audit Code'
$department = Read-Required 'Phong ban'
$employee = Read-Required 'Ho va ten'

try {
    Write-Host ''
    Write-Host 'Dang kiem tra Audit Code...' -ForegroundColor Cyan
    $validation = Test-AuditCode -Code $code
    if (-not $validation.ok) { throw 'Audit Code khong hop le.' }

    $customer = $validation.data.customer
    $branch = $validation.data.branch

    Write-Host "Cong ty  : $($customer.name)"
    Write-Host "Chi nhanh: $($branch.name)"
    Write-Host ''
    $confirm = Read-Host 'Thong tin dung? Tiep tuc (Y/N)'
    if ($confirm -notmatch '^(Y|y)$') { Write-Host 'Da huy.'; exit 0 }

    Write-Host ''
    Write-Host 'Dang thu thap thong tin may...' -ForegroundColor Cyan
    $data = Get-AuditInventory

    Write-Host 'Dang gui du lieu ve he thong...' -ForegroundColor Cyan
    $result = Submit-Audit -Code $code -Department $department -EmployeeName $employee -Data $data

    if (-not $result.ok) { throw 'He thong khong chap nhan du lieu Audit.' }

    Write-Host ''
    Write-Host '=========================================' -ForegroundColor Green
    Write-Host ' AUDIT HOAN TAT' -ForegroundColor Green
    Write-Host " Ma Audit : $($result.id)"
    Write-Host ' Du lieu da duoc gui ve he thong.'
    Write-Host '=========================================' -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host 'AUDIT THAT BAI' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Nhan Enter de thoat'
    exit 1
}
