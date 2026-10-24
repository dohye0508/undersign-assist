# 대회장 패드 모드: 같은 와이파이의 안드로이드 패드에서 카메라까지 되게 앱과 API를 HTTPS로 띄운다.
#
#   powershell -ExecutionPolicy Bypass -File scripts/pad-serve.ps1
#
# 하는 일: 1) LAN IP 찾기  2) 자체 서명 인증서 만들기  3) flutter build web (API_BASE=https://<ip>:8443)
#         4) 백엔드를 0.0.0.0:8443 HTTPS 로  5) 빌드 결과를 0.0.0.0:3443 HTTPS 로  6) 패드에서 열 주소 안내
# 주의: 서버가 와이파이 전체에 열린다. 시연 중에만 쓰고, 끝나면 두 창을 닫는다.
# Windows PowerShell 5.1 기준 (&&, 삼항 연산자 쓰지 않음).

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Root       = Split-Path -Parent $PSScriptRoot
$AppDir     = Join-Path $Root 'app'
$BackendDir = Join-Path $Root 'backend'
$SamplesDir = Join-Path $Root 'samples'
$BuildDir   = Join-Path $AppDir 'build\web'
$CertDir    = Join-Path $BackendDir '.certs'
$CertPath   = Join-Path $CertDir 'cert.pem'
$KeyPath    = Join-Path $CertDir 'key.pem'
$VenvPython = Join-Path $BackendDir '.venv\Scripts\python.exe'
$ApiPort    = 8443
$WebPort    = 3443

function Step([string]$Text) {
    Write-Host ''
    Write-Host ('==> ' + $Text) -ForegroundColor Cyan
}

# ---------- 0. 준비물 확인 ----------
if (-not (Test-Path $VenvPython)) {
    Write-Host "backend\.venv 가 없습니다. CLAUDE.md '실행' 절대로 먼저 가상환경을 만드세요." -ForegroundColor Red
    exit 1
}
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -eq $flutter) {
    Write-Host "flutter 명령을 찾을 수 없습니다. PATH를 확인하세요." -ForegroundColor Red
    exit 1
}

# ---------- 1. LAN IP ----------
Step 'LAN IP 찾기'
$Ip = '127.0.0.1'
try {
    $addr = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' -or $_.IPAddress -like '172.*' } |
        Select-Object -First 1
    if ($null -ne $addr) { $Ip = $addr.IPAddress }
} catch { }
if ($Ip -eq '127.0.0.1') {
    Write-Host '와이파이 IP를 찾지 못해 127.0.0.1 을 씁니다. 패드에서는 열 수 없습니다.' -ForegroundColor Yellow
} else {
    Write-Host ('이 노트북의 IP: ' + $Ip)
}
$ApiBase = 'https://' + $Ip + ':' + $ApiPort
$WebUrl  = 'https://' + $Ip + ':' + $WebPort

# ---------- 2. 인증서 ----------
Step '자체 서명 인증서 확인/생성'
& $VenvPython -c 'import cryptography' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'cryptography 패키지를 backend\.venv 에 설치합니다...'
    & $VenvPython -m pip install cryptography
    if ($LASTEXITCODE -ne 0) { Write-Host 'cryptography 설치 실패' -ForegroundColor Red; exit 1 }
}
& $VenvPython (Join-Path $PSScriptRoot 'make_cert.py') $Ip
if ($LASTEXITCODE -ne 0) { Write-Host '인증서 생성 실패' -ForegroundColor Red; exit 1 }

# ---------- 3. Flutter 웹 빌드 ----------
Step ('flutter build web  (API_BASE=' + $ApiBase + ')  -- 몇 분 걸립니다')
Push-Location $AppDir
try {
    & flutter build web --dart-define=("API_BASE=" + $ApiBase)
    $buildExit = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($buildExit -ne 0) { Write-Host 'flutter build web 실패' -ForegroundColor Red; exit 1 }
if (-not (Test-Path (Join-Path $BuildDir 'index.html'))) {
    Write-Host ('빌드 결과가 없습니다: ' + $BuildDir) -ForegroundColor Red
    exit 1
}
if (Test-Path $SamplesDir) {
    $pngs = Get-ChildItem -Path $SamplesDir -Filter '*.png' -File -ErrorAction SilentlyContinue
    if ($pngs.Count -gt 0) {
        Copy-Item -Path (Join-Path $SamplesDir '*.png') -Destination $BuildDir -Force
        Write-Host ('샘플 ' + $pngs.Count + '장을 build\web 에 복사했습니다.')
    }
}

# ---------- 4. 백엔드 (HTTPS, 0.0.0.0:8443) ----------
Step ('백엔드 시작: 0.0.0.0:' + $ApiPort + ' (새 창)')
$backendArgs = @(
    '-m', 'uvicorn', 'app.main:app',
    '--host', '0.0.0.0', '--port', "$ApiPort",
    '--ssl-keyfile', ('"' + $KeyPath + '"'),
    '--ssl-certfile', ('"' + $CertPath + '"')
)
$backendProc = Start-Process -FilePath $VenvPython -ArgumentList $backendArgs -WorkingDirectory $BackendDir -PassThru

# ---------- 5. 정적 서버 (HTTPS, 0.0.0.0:3443) ----------
Step ('앱 정적 서버 시작: 0.0.0.0:' + $WebPort + ' (새 창)')
$staticArgs = @(
    ('"' + (Join-Path $PSScriptRoot 'https_static.py') + '"'),
    ('"' + $BuildDir + '"'),
    "$WebPort",
    ('"' + $CertPath + '"'),
    ('"' + $KeyPath + '"')
)
$staticProc = Start-Process -FilePath $VenvPython -ArgumentList $staticArgs -WorkingDirectory $Root -PassThru

# ---------- 6. 안내 ----------
$line = '=' * 72
Write-Host ''
Write-Host $line -ForegroundColor Green
Write-Host '   대회장 패드 모드 준비 완료' -ForegroundColor Green
Write-Host $line -ForegroundColor Green
Write-Host ''
Write-Host '  패드와 이 노트북이 같은 와이파이에 있어야 합니다.' -ForegroundColor White
Write-Host ''
Write-Host '  1) 패드 크롬에서 먼저 이 주소를 한 번 엽니다 (API 인증서 경고 통과):' -ForegroundColor Yellow
Write-Host ('       ' + $ApiBase + '/api/health') -ForegroundColor Yellow
Write-Host '     "연결이 비공개로 설정되어 있지 않습니다" 화면이 나오면'
Write-Host '       [고급] -> [안전하지 않음(으)로 이동] 을 누릅니다.  {"status":"ok"} 비슷한 글자가 보이면 됩니다.'
Write-Host ''
Write-Host '  2) 그다음 앱 주소를 엽니다 (여기서도 같은 경고를 한 번 더 통과):' -ForegroundColor Yellow
Write-Host ('       ' + $WebUrl) -ForegroundColor Yellow
Write-Host ''
Write-Host '  3) 카메라 권한을 물으면 허용합니다. 진동은 안드로이드 크롬에서만 됩니다.'
Write-Host ''
Write-Host '  끝나면: 새로 뜬 두 창(백엔드, 정적 서버)을 닫습니다. 서버가 와이파이에 열려 있으니 꼭 닫으세요.' -ForegroundColor Magenta
Write-Host ('       PID: 백엔드 ' + $backendProc.Id + ', 정적 서버 ' + $staticProc.Id)
Write-Host ''
Write-Host '  패드에서 안 열리면(방화벽): 관리자 PowerShell에서 아래 두 줄을 실행합니다.' -ForegroundColor Cyan
Write-Host '       netsh advfirewall firewall add rule name="undersign 3443" dir=in action=allow protocol=TCP localport=3443'
Write-Host '       netsh advfirewall firewall add rule name="undersign 8443" dir=in action=allow protocol=TCP localport=8443'
Write-Host '     시연이 끝나면 지웁니다:'
Write-Host '       netsh advfirewall firewall delete rule name="undersign 3443"'
Write-Host '       netsh advfirewall firewall delete rule name="undersign 8443"'
Write-Host ''
Write-Host $line -ForegroundColor Green
