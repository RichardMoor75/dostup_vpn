# Dostup Installer for Mihomo (Windows)
# ============================================

$ErrorActionPreference = 'Stop'

# Enable TLS 1.2 for older Windows versions (Win 7/8)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$DOSTUP_DIR = "$env:USERPROFILE\dostup"
$LOGS_DIR = "$DOSTUP_DIR\logs"
$CONFIG_FILE = "$DOSTUP_DIR\config.yaml"
$SETTINGS_FILE = "$DOSTUP_DIR\settings.json"
$MIHOMO_BIN = "$DOSTUP_DIR\mihomo.exe"
$DESKTOP = [Environment]::GetFolderPath('Desktop')

$MIHOMO_API = 'https://api.github.com/repos/MetaCubeX/mihomo/releases/latest'
$GEOIP_URL = 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat'
$GEOSITE_URL = 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat'
$ICON_URL = 'https://files.richard-moor.ru/Install/dostup_vpn/icon.ico'

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
        # Проверяем что это не HTML-страница (ошибка сервера)
        if ($content -match '(?i)<!DOCTYPE|<html|<head') {
            return $false
        }
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

function Expand-ZipFile($zipPath, $destPath) {
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Expand-Archive -Path $zipPath -DestinationPath $destPath -Force
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destPath)
    }
}

function Get-FileSHA256($path) {
    if ($PSVersionTable.PSVersion.Major -ge 4) {
        return (Get-FileHash -Path $path -Algorithm SHA256).Hash
    } else {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $stream = [System.IO.File]::OpenRead($path)
        try {
            $hash = $sha256.ComputeHash($stream)
            return [BitConverter]::ToString($hash) -replace '-', ''
        } finally {
            $stream.Close()
        }
    }
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

# Save old subscription if exists
$oldSubUrl = ''
if (Test-Path $SETTINGS_FILE) {
    try {
        $oldSettings = Get-Content $SETTINGS_FILE -Raw | ConvertFrom-Json
        $oldSubUrl = $oldSettings.subscription_url
    } catch { }
}

# Stop mihomo if running
$mihomoProcess = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
if ($mihomoProcess) {
    Write-Step 'Stopping running Mihomo...'
    Start-Process -FilePath 'taskkill' -ArgumentList '/F /IM mihomo.exe' -Verb RunAs -Wait -WindowStyle Hidden
    # Wait with timeout
    $stopTimeout = 10
    while ((Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) -and $stopTimeout -gt 0) {
        Start-Sleep -Seconds 1
        $stopTimeout--
    }
    if (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) {
        Write-Fail 'Could not stop Mihomo. Please restart your computer and try again.'
        Read-Host 'Press Enter to close'
        exit 1
    }
    Write-OK 'Mihomo stopped'
}

# Remove old installation
if (Test-Path $DOSTUP_DIR) {
    Write-Step 'Removing old installation...'
    # Retry removal in case files are still locked
    $retries = 3
    while ((Test-Path $DOSTUP_DIR) -and $retries -gt 0) {
        Remove-Item -Recurse -Force $DOSTUP_DIR -ErrorAction SilentlyContinue
        if (Test-Path $DOSTUP_DIR) {
            Start-Sleep -Seconds 2
            $retries--
        }
    }
    if (Test-Path $DOSTUP_DIR) {
        Write-Fail 'Could not remove old installation. Please close all programs using dostup folder and try again.'
        Read-Host 'Press Enter to close'
        exit 1
    }
    Write-OK 'Old installation removed'
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
    $headers = @{ 'User-Agent' = 'Dostup-Installer' }
    $release = Invoke-RestMethod -Uri $MIHOMO_API -Headers $headers
    $version = $release.tag_name
    Write-OK "Version: $version"
} catch {
    Write-Fail "Failed to get version: $_"
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
        $actualHash = Get-FileSHA256 $zipPath
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
    Expand-ZipFile $zipPath $DOSTUP_DIR
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

$subUrl = ''
if (-not [string]::IsNullOrEmpty($oldSubUrl)) {
    # Ask: keep old or enter new
    Write-Info 'Previous subscription found'
    Write-Host ''
    Write-Host '1) Keep current subscription'
    Write-Host '2) Enter new subscription'
    Write-Host ''
    $choice = Read-Host 'Choose (1 or 2)'

    if ($choice -eq '2') {
        $subUrl = [Microsoft.VisualBasic.Interaction]::InputBox('Enter subscription URL (config):', 'Dostup', '')
    } else {
        $subUrl = $oldSubUrl
        Write-OK 'Using previous subscription'
    }
} else {
    $subUrl = [Microsoft.VisualBasic.Interaction]::InputBox('Enter subscription URL (config):', 'Dostup', '')
}

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
}
if ($geoSuccess) {
    $settings.last_geo_update = (Get-Date -Format 'yyyy-MM-dd')
}
$settings | ConvertTo-Json | Set-Content -Path $SETTINGS_FILE -Encoding UTF8

# Create sites.json for access checking
$sitesFile = "$DOSTUP_DIR\sites.json"
if (-not (Test-Path $sitesFile)) {
    $sitesContent = @{
        sites = @(
            "instagram.com",
            "youtube.com",
            "facebook.com",
            "rutracker.org",
            "hdrezka.ag",
            "flibusta.is"
        )
    }
    $sitesContent | ConvertTo-Json | Set-Content -Path $sitesFile -Encoding UTF8
}

Write-Step 'Creating control script...'

$controlPs1 = @'
# Enable TLS 1.2 for older Windows versions (Win 7/8)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$DOSTUP_DIR = "$env:USERPROFILE\dostup"
$SETTINGS_FILE = "$DOSTUP_DIR\settings.json"
$MIHOMO_BIN = "$DOSTUP_DIR\mihomo.exe"
$CONFIG_FILE = "$DOSTUP_DIR\config.yaml"
$SITES_FILE = "$DOSTUP_DIR\sites.json"
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
        if ($c -match '(?i)<!DOCTYPE|<html|<head') { return $false }
        return ($c -match '^\s*[\w-]+\s*:' -or $c -match '^\s*-\s+')
    } catch { return $false }
}

function Expand-ZipFile($zipPath, $destPath) {
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Expand-Archive -Path $zipPath -DestinationPath $destPath -Force
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destPath)
    }
}

function Test-SiteAccess {
    Write-Host ''
    Write-Step 'Проверка доступа к ресурсам...'
    Write-Host ''

    if (-not (Test-Path $SITES_FILE)) {
        Write-Fail 'Файл sites.json не найден'
        return
    }

    try {
        $sitesData = Get-Content $SITES_FILE -Raw | ConvertFrom-Json
        $sites = $sitesData.sites
    } catch {
        Write-Fail 'Не удалось прочитать список сайтов'
        return
    }

    foreach ($site in $sites) {
        try {
            $null = Invoke-WebRequest -Uri "https://$site" -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            Write-Host "[OK] $site — доступен" -ForegroundColor Green
        } catch {
            Write-Host "[X] $site — недоступен" -ForegroundColor Red
        }
    }

    Write-Host ''
}

function Stop-Mihomo {
    Write-Step 'Stopping Mihomo (requires admin)...'
    Start-Process -FilePath 'taskkill' -ArgumentList '/F /IM mihomo.exe' -Verb RunAs -Wait -WindowStyle Hidden
    # Wait with timeout
    $stopTimeout = 10
    while ((Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) -and $stopTimeout -gt 0) {
        Start-Sleep -Seconds 1
        $stopTimeout--
    }
    $proc = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-OK 'Mihomo stopped'
        return $true
    } else {
        Write-Fail 'Could not stop. Try restarting your computer.'
        return $false
    }
}

function Start-Mihomo {
    $settings = Get-Content $SETTINGS_FILE | ConvertFrom-Json

    Write-Step 'Checking for core updates...'
    try {
        $headers = @{ 'User-Agent' = 'Dostup-Installer' }
        $rel = Invoke-RestMethod -Uri $MIHOMO_API -Headers $headers
        $latest = $rel.tag_name
        if ($settings.installed_version -ne $latest) {
            Write-Step "Updating: $($settings.installed_version) -> $latest"
            $arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { '386' }
            if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
            $fn = "mihomo-windows-$arch-$latest.zip"
            $url = "https://github.com/MetaCubeX/mihomo/releases/download/$latest/$fn"
            if (Invoke-DownloadWithRetry $url "$DOSTUP_DIR\m.zip") {
                Expand-ZipFile "$DOSTUP_DIR\m.zip" $DOSTUP_DIR
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

    # Обновление geo-баз (раз в 2 недели)
    $shouldUpdateGeo = $false
    try {
        if ($settings.last_geo_update) {
            $lastGeo = [DateTime]::Parse($settings.last_geo_update)
            if (((Get-Date) - $lastGeo).Days -ge 14) { $shouldUpdateGeo = $true }
        } else { $shouldUpdateGeo = $true }
    } catch { $shouldUpdateGeo = $true }

    if ($shouldUpdateGeo) {
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
        return $true
    } else {
        Write-Fail 'Failed to start'
        Write-Host "Logs: $DOSTUP_DIR\logs"
        return $false
    }
}

# === MAIN ===

Write-Host ''
Write-Host '=== Dostup VPN ===' -ForegroundColor Blue
Write-Host ''

$proc = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
if ($proc) {
    # Mihomo is running - show menu
    Write-Host 'Mihomo is running' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Panel: https://metacubex.github.io/metacubexd/'
    Write-Host 'API: 127.0.0.1:9090'
    Write-Host ''
    Write-Host '1) Stop'
    Write-Host '2) Restart'
    Write-Host '3) Check access'
    Write-Host '4) Cancel'
    Write-Host ''
    $choice = Read-Host 'Choose (1-4)'

    switch ($choice) {
        '1' {
            Stop-Mihomo
            Write-Host ''
            Write-Host 'Window will close in 3 seconds...'
            Start-Sleep -Seconds 3
        }
        '2' {
            Stop-Mihomo
            Write-Host ''
            Start-Mihomo
            Write-Host ''
            Write-Host 'Window will close in 5 seconds...'
            Start-Sleep -Seconds 5
        }
        '3' {
            Test-SiteAccess
            Read-Host 'Press Enter to close'
        }
        default {
            Write-Host ''
            Write-Host 'Cancelled'
            Write-Host ''
            Write-Host 'Window will close in 2 seconds...'
            Start-Sleep -Seconds 2
        }
    }
} else {
    # Mihomo is not running - start without asking
    Start-Mihomo
    Write-Host ''
    Write-Host 'Window will close in 5 seconds...'
    Start-Sleep -Seconds 5
}
'@
$controlPs1 | Set-Content -Path "$DOSTUP_DIR\Dostup_VPN.ps1" -Encoding UTF8

# Remove old scripts if exist
Remove-Item "$DOSTUP_DIR\dostup-start.ps1" -Force -ErrorAction SilentlyContinue
Remove-Item "$DOSTUP_DIR\dostup-stop.ps1" -Force -ErrorAction SilentlyContinue

Write-OK 'Control script created'

Write-Step 'Downloading icon...'
$iconPath = "$DOSTUP_DIR\icon.ico"
if (Invoke-DownloadWithRetry $ICON_URL $iconPath) {
    Write-OK 'Icon downloaded'
} else {
    Write-Fail 'Icon download failed (shortcut will use default icon)'
}

Write-Step 'Creating desktop shortcut...'
$WshShell = New-Object -ComObject WScript.Shell

# Remove old shortcuts if exist
Remove-Item "$DESKTOP\Dostup Start.lnk" -Force -ErrorAction SilentlyContinue
Remove-Item "$DESKTOP\Dostup Stop.lnk" -Force -ErrorAction SilentlyContinue

# Create new shortcut
$vpnLnk = $WshShell.CreateShortcut("$DESKTOP\Dostup_VPN.lnk")
$vpnLnk.TargetPath = "powershell.exe"
$vpnLnk.Arguments = "-ExecutionPolicy Bypass -File `"$DOSTUP_DIR\Dostup_VPN.ps1`""
$vpnLnk.WorkingDirectory = $DOSTUP_DIR
if (Test-Path $iconPath) {
    $vpnLnk.IconLocation = "$iconPath,0"
}
$vpnLnk.Save()

Write-OK 'Shortcut created'

Write-Step 'Configuring firewall...'
try {
    # netsh requires admin rights - run all commands in one elevated cmd to avoid multiple UAC prompts
    $fwCommands = @(
        "netsh advfirewall firewall delete rule name=all program=`"$MIHOMO_BIN`"",
        "netsh advfirewall firewall add rule name=`"Mihomo Proxy (Inbound)`" dir=in action=allow program=`"$MIHOMO_BIN`" enable=yes profile=any",
        "netsh advfirewall firewall add rule name=`"Mihomo Proxy (Outbound)`" dir=out action=allow program=`"$MIHOMO_BIN`" enable=yes profile=any"
    ) -join ' & '

    Start-Process -FilePath 'cmd' -ArgumentList "/c $fwCommands" -Verb RunAs -Wait -WindowStyle Hidden

    Write-OK 'Firewall configured'
} catch {
    Write-Info 'Firewall: manual configuration may be needed'
}

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
    Write-Host 'Desktop shortcut:'
    Write-Host '  - Dostup_VPN'
    Write-Host ''
} else {
    Write-Host '[FAIL] Failed to start Mihomo' -ForegroundColor Red
    Write-Host "Check logs: $LOGS_DIR"
}

Write-Host ''
Write-Host 'Window will close in 5 seconds...'
Start-Sleep -Seconds 5
