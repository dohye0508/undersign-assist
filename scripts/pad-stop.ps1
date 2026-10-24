# 대회장 패드 모드 서버(8443 API, 3443 앱)를 끈다. pad-serve.ps1이 창 없이 띄우므로 이걸로 끈다.
#
#   powershell -ExecutionPolicy Bypass -File scripts/pad-stop.ps1

foreach ($port in @(8443, 3443)) {
    $found = $false
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        $found = $true
        Stop-Process -Id $_.OwningProcess -Force -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host ('끔: ' + $port + ' (PID ' + $_.OwningProcess + ')')
    }
    if (-not $found) { Write-Host ('이미 꺼져 있음: ' + $port) }
}
