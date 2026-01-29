# Dostup Installer for Mihomo (Windows)
# ============================================

$ErrorActionPreference = 'Stop'

$DOSTUP_DIR = "$env:USERPROFILE\dostup"
$LOGS_DIR = "$DOSTUP_DIR\logs"
$CONFIG_FILE = "$DOSTUP_DIR\config.yaml"
$SETTINGS_FILE = "$DOSTUP_DIR\settings.json"
$MIHOMO_BIN = "$DOSTUP_DIR\mihomo.exe"
$DESKTOP = [Environment]::GetFolderPath('Desktop')

$MIHOMO_API = 'https://api.github.com/repos/MetaCubeX/mihomo/releases/latest'
$GEOIP_URL = 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat'
$GEOSITE_URL = 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat'

function Write-Step($text) { Write-Host "> $text" -ForegroundColor Yellow }
function Write-OK($text) { Write-Host "[OK] $text" -ForegroundColor Green }
function Write-Fail($text) { Write-Host "[FAIL] $text" -ForegroundColor Red }
function Write-Info($text) { Write-Host "[i] $text" -ForegroundColor Blue }

function Test-ValidUrl($url) {
    return $url -match '^https?://'
}

function Test-ValidYaml($path) {
    try {
        $content = Get-Content $path -Raw
        # Простая проверка на базовый YAML синтаксис
        if ($content -match '^\s*[\w-]+\s*:' -or $content -match '^\s*-\s+') {
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

function Invoke-DownloadWithRetry($url, $output, $maxRetries = 3) {
    $retry = 0
    while ($retry -lt $maxRetries) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing
            return $true
        } catch {
            $retry++
            if ($retry -lt $maxRetries) {
                Write-Info "Retry ($retry/$maxRetries)..."
                Start-Sleep -Seconds 2
            }
        }
    }
    return $false
}

function Backup-Config {
    if (Test-Path $CONFIG_FILE) {
        Copy-Item $CONFIG_FILE "$CONFIG_FILE.backup" -Force
    }
}

function Restore-Config {
    if (Test-Path "$CONFIG_FILE.backup") {
        Move-Item "$CONFIG_FILE.backup" $CONFIG_FILE -Force
    }
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Blue
Write-Host '       Dostup Installer for Mihomo' -ForegroundColor Blue
Write-Host '============================================' -ForegroundColor Blue
Write-Host ''

if ((Test-Path $MIHOMO_BIN) -and (Test-Path $SETTINGS_FILE)) {
    Write-Host 'Installation found. Use Dostup Start on desktop.' -ForegroundColor Blue
    Write-Host ''
    Read-Host 'Press Enter to close'
    exit
}

Write-Step 'Checking internet...'
try {
    $null = Invoke-WebRequest -Uri 'https://github.com' -UseBasicParsing -TimeoutSec 5
    Write-OK 'Internet OK'
} catch {
    Write-Fail 'No internet connection'
    Read-Host 'Press Enter to close'
    exit 1
}

Write-Step 'Creating folder...'
New-Item -ItemType Directory -Force -Path $DOSTUP_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $LOGS_DIR | Out-Null
Write-OK 'Folder created'

Write-Step 'Detecting architecture...'
$arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { '386' }
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
Write-OK "Architecture: $arch"

Write-Step 'Getting latest mihomo version...'
try {
    $release = Invoke-RestMethod -Uri $MIHOMO_API -UseBasicParsing
    $version = $release.tag_name
    Write-OK "Version: $version"
} catch {
    Write-Fail 'Failed to get version'
    Read-Host 'Press Enter to close'
    exit 1
}

Write-Step 'Downloading mihomo...'
$filename = "mihomo-windows-$arch-$version.zip"
$downloadUrl = "https://github.com/MetaCubeX/mihomo/releases/download/$version/$filename"
$zipPath = "$DOSTUP_DIR\mihomo.zip"

if (-not (Invoke-DownloadWithRetry $downloadUrl $zipPath)) {
    Write-Fail 'Download failed'
    Read-Host 'Press Enter to close'
    exit 1
}

# Verify SHA256 (if available)
Write-Step 'Verifying file integrity...'
$checksumUrl = "https://github.com/MetaCubeX/mihomo/releases/download/$version/$filename.sha256"
try {
    $expectedHash = (Invoke-WebRequest -Uri $checksumUrl -UseBasicParsing -ErrorAction Stop).Content.Trim().Split()[0]
    # Check if it looks like SHA256 (64 hex chars)
    if ($expectedHash -match '^[a-fA-F0-9]{64}$') {
        $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
        if ($expectedHash.ToUpper() -ne $actualHash.ToUpper()) {
            Write-Fail 'Hash mismatch! File corrupted.'
            Remove-Item $zipPath -Force
            Read-Host 'Press Enter to close'
            exit 1
        }
        Write-OK 'Hash verified'
    } else {
        Write-Info 'SHA256 not found, skipping verification'
    }
} catch {
    Write-Info 'SHA256 not found, skipping verification'
}

try {
    Expand-Archive -Path $zipPath -DestinationPath $DOSTUP_DIR -Force
    Remove-Item $zipPath -Force
    $exeFile = Get-ChildItem -Path $DOSTUP_DIR -Filter 'mihomo*.exe' | Select-Object -First 1
    if ($exeFile -and $exeFile.Name -ne 'mihomo.exe') {
        Rename-Item -Path $exeFile.FullName -NewName 'mihomo.exe' -Force
    }
    Write-OK 'Mihomo downloaded'
} catch {
    Write-Fail "Extract failed: $_"
    Read-Host 'Press Enter to close'
    exit 1
}

Write-Step 'Setup subscription...'
Add-Type -AssemblyName Microsoft.VisualBasic
$subUrl = [Microsoft.VisualBasic.Interaction]::InputBox('Enter subscription URL (config):', 'Dostup', '')
if ([string]::IsNullOrEmpty($subUrl)) {
    Write-Fail 'Subscription URL not provided'
    Read-Host 'Press Enter to close'
    exit 1
}
if (-not (Test-ValidUrl $subUrl)) {
    Write-Fail 'Invalid URL format. URL must start with http:// or https://'
    Read-Host 'Press Enter to close'
    exit 1
}

Write-Step 'Downloading config...'
Backup-Config
$tempConfig = "$CONFIG_FILE.tmp"

if (-not (Invoke-DownloadWithRetry $subUrl $tempConfig)) {
    Write-Fail 'Failed to download config'
    Restore-Config
    Read-Host 'Press Enter to close'
    exit 1
}

if (-not (Test-ValidYaml $tempConfig)) {
    Write-Fail 'Downloaded config is not valid YAML'
    Remove-Item $tempConfig -Force -ErrorAction SilentlyContinue
    Restore-Config
    Read-Host 'Press Enter to close'
    exit 1
}

Move-Item $tempConfig $CONFIG_FILE -Force
Write-OK 'Config downloaded and verified'

Write-Step 'Downloading geo databases...'
$geoSuccess = $true
if (-not (Invoke-DownloadWithRetry $GEOIP_URL "$DOSTUP_DIR\geoip.dat")) {
    Write-Fail 'Failed to download geoip.dat'
    $geoSuccess = $false
}
if (-not (Invoke-DownloadWithRetry $GEOSITE_URL "$DOSTUP_DIR\geosite.dat")) {
    Write-Fail 'Failed to download geosite.dat'
    $geoSuccess = $false
}
if ($geoSuccess) {
    Write-OK 'Geo databases downloaded'
}

$settings = @{
    subscription_url = $subUrl
    installed_version = $version
    last_geo_update = (Get-Date -Format 'yyyy-MM-dd')
}
$settings | ConvertTo-Json | Set-Content -Path $SETTINGS_FILE -Encoding UTF8

Write-Step 'Creating scripts...'

$startPs1 = @'
$DOSTUP_DIR = "$env:USERPROFILE\dostup"
$SETTINGS_FILE = "$DOSTUP_DIR\settings.json"
$MIHOMO_BIN = "$DOSTUP_DIR\mihomo.exe"
$CONFIG_FILE = "$DOSTUP_DIR\config.yaml"
$MIHOMO_API = 'https://api.github.com/repos/MetaCubeX/mihomo/releases/latest'
$GEOIP_URL = 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat'
$GEOSITE_URL = 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat'

function Write-Step($t) { Write-Host "> $t" -ForegroundColor Yellow }
function Write-OK($t) { Write-Host "[OK] $t" -ForegroundColor Green }
function Write-Fail($t) { Write-Host "[FAIL] $t" -ForegroundColor Red }
function Write-Info($t) { Write-Host "[i] $t" -ForegroundColor Blue }

function Invoke-DownloadWithRetry($url, $output) {
    $retry = 0
    while ($retry -lt 3) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing
            return $true
        } catch {
            $retry++
            if ($retry -lt 3) { Write-Info "Retry ($retry/3)..."; Start-Sleep -Seconds 2 }
        }
    }
    return $false
}

function Test-ValidYaml($path) {
    try {
        $c = Get-Content $path -Raw
        return ($c -match '^\s*[\w-]+\s*:' -or $c -match '^\s*-\s+')
    } catch { return $false }
}

Write-Host ''
Write-Host '=== Dostup Start ===' -ForegroundColor Blue
Write-Host ''

$proc = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host 'Mihomo is already running' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Panel: https://metacubex.github.io/metacubexd/'
    Write-Host 'API: 127.0.0.1:9090'
    Write-Host ''
    Read-Host 'Press Enter'
    exit
}

$settings = Get-Content $SETTINGS_FILE | ConvertFrom-Json

Write-Step 'Checking for core updates...'
try {
    $rel = Invoke-RestMethod -Uri $MIHOMO_API -UseBasicParsing
    $latest = $rel.tag_name
    if ($settings.installed_version -ne $latest) {
        Write-Step "Updating: $($settings.installed_version) -> $latest"
        $arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { '386' }
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
        $fn = "mihomo-windows-$arch-$latest.zip"
        $url = "https://github.com/MetaCubeX/mihomo/releases/download/$latest/$fn"
        if (Invoke-DownloadWithRetry $url "$DOSTUP_DIR\m.zip") {
            Expand-Archive -Path "$DOSTUP_DIR\m.zip" -DestinationPath $DOSTUP_DIR -Force
            Remove-Item "$DOSTUP_DIR\m.zip" -Force
            $exe = Get-ChildItem -Path $DOSTUP_DIR -Filter 'mihomo*.exe' | Select-Object -First 1
            if ($exe -and $exe.Name -ne 'mihomo.exe') {
                Remove-Item $MIHOMO_BIN -Force -ErrorAction SilentlyContinue
                Rename-Item -Path $exe.FullName -NewName 'mihomo.exe' -Force
            }
            $settings.installed_version = $latest
            $settings | ConvertTo-Json | Set-Content -Path $SETTINGS_FILE -Encoding UTF8
            Write-OK 'Core updated'
        } else { Write-Fail 'Update failed, using current version' }
    } else { Write-OK 'Core is up to date' }
} catch { Write-OK 'Core is up to date' }

Write-Step 'Downloading config...'
if (Test-Path $CONFIG_FILE) { Copy-Item $CONFIG_FILE "$CONFIG_FILE.backup" -Force }
$tempCfg = "$CONFIG_FILE.tmp"
if (Invoke-DownloadWithRetry $settings.subscription_url $tempCfg) {
    if (Test-ValidYaml $tempCfg) {
        Move-Item $tempCfg $CONFIG_FILE -Force
        Write-OK 'Config updated'
    } else {
        Write-Fail 'Invalid YAML, using old config'
        Remove-Item $tempCfg -Force -ErrorAction SilentlyContinue
        if (Test-Path "$CONFIG_FILE.backup") { Move-Item "$CONFIG_FILE.backup" $CONFIG_FILE -Force }
    }
} else {
    Write-Fail 'Using old config'
    if (Test-Path "$CONFIG_FILE.backup") { Move-Item "$CONFIG_FILE.backup" $CONFIG_FILE -Force }
}

$lastGeo = [DateTime]::Parse($settings.last_geo_update)
if (((Get-Date) - $lastGeo).Days -ge 14) {
    Write-Step 'Updating geo databases...'
    $geoOk = $true
    if (-not (Invoke-DownloadWithRetry $GEOIP_URL "$DOSTUP_DIR\geoip.dat")) { $geoOk = $false }
    if (-not (Invoke-DownloadWithRetry $GEOSITE_URL "$DOSTUP_DIR\geosite.dat")) { $geoOk = $false }
    if ($geoOk) {
        $settings.last_geo_update = (Get-Date -Format 'yyyy-MM-dd')
        $settings | ConvertTo-Json | Set-Content -Path $SETTINGS_FILE -Encoding UTF8
        Write-OK 'Geo databases updated'
    }
}

Write-Step 'Starting Mihomo...'
Write-Host ''
Start-Process -FilePath $MIHOMO_BIN -ArgumentList "-d `"$DOSTUP_DIR`"" -Verb RunAs -WindowStyle Hidden
Start-Sleep -Seconds 3

$proc = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host ''
    Write-Host '============================================' -ForegroundColor Green
    Write-Host '[OK] Mihomo started successfully!' -ForegroundColor Green
    Write-Host '============================================' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Panel: https://metacubex.github.io/metacubexd/'
    Write-Host 'API: 127.0.0.1:9090'
    Write-Host ''
    Write-Host 'Window will close in 5 seconds...'
    Start-Sleep -Seconds 5
} else {
    Write-Fail 'Failed to start'
    Write-Host "Logs: $DOSTUP_DIR\logs"
    Read-Host 'Press Enter'
}
'@
$startPs1 | Set-Content -Path "$DOSTUP_DIR\dostup-start.ps1" -Encoding UTF8

$stopPs1 = @'
Write-Host ''
Write-Host '=== Dostup Stop ===' -ForegroundColor Blue
Write-Host ''
$proc = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host 'Mihomo is not running' -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    exit
}
Write-Host '> Stopping Mihomo (requires admin)...' -ForegroundColor Yellow
Start-Process -FilePath 'taskkill' -ArgumentList '/F /IM mihomo.exe' -Verb RunAs -Wait -WindowStyle Hidden
Start-Sleep -Seconds 2
$proc = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host ''
    Write-Host '[OK] Mihomo stopped' -ForegroundColor Green
    Write-Host 'Window will close in 3 seconds...'
    Start-Sleep -Seconds 3
} else {
    Write-Host '[FAIL] Could not stop' -ForegroundColor Red
    Write-Host 'Try running as Administrator'
    Read-Host 'Press Enter'
}
'@
$stopPs1 | Set-Content -Path "$DOSTUP_DIR\dostup-stop.ps1" -Encoding UTF8

Write-OK 'Scripts created'

Write-Step 'Creating desktop shortcuts...'
$WshShell = New-Object -ComObject WScript.Shell

$startLnk = $WshShell.CreateShortcut("$DESKTOP\Dostup Start.lnk")
$startLnk.TargetPath = "powershell.exe"
$startLnk.Arguments = "-ExecutionPolicy Bypass -File `"$DOSTUP_DIR\dostup-start.ps1`""
$startLnk.WorkingDirectory = $DOSTUP_DIR
$startLnk.Save()

$stopLnk = $WshShell.CreateShortcut("$DESKTOP\Dostup Stop.lnk")
$stopLnk.TargetPath = "powershell.exe"
$stopLnk.Arguments = "-ExecutionPolicy Bypass -File `"$DOSTUP_DIR\dostup-stop.ps1`""
$stopLnk.WorkingDirectory = $DOSTUP_DIR
$stopLnk.Save()

Write-OK 'Shortcuts created'

Write-Step 'Starting Mihomo...'
Write-Host ''
Start-Process -FilePath $MIHOMO_BIN -ArgumentList "-d `"$DOSTUP_DIR`"" -Verb RunAs -WindowStyle Hidden
Start-Sleep -Seconds 3

$process = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
if ($process) {
    Write-Host ''
    Write-Host '============================================' -ForegroundColor Green
    Write-Host '    Installation completed!' -ForegroundColor Green
    Write-Host '============================================' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Panel: https://metacubex.github.io/metacubexd/'
    Write-Host 'API: 127.0.0.1:9090'
    Write-Host ''
    Write-Host 'Desktop shortcuts:'
    Write-Host '  - Dostup Start'
    Write-Host '  - Dostup Stop'
    Write-Host ''
} else {
    Write-Host '[FAIL] Failed to start Mihomo' -ForegroundColor Red
    Write-Host "Check logs: $LOGS_DIR"
}

Write-Host ''
Write-Host 'Window will close in 5 seconds...'
Start-Sleep -Seconds 5
