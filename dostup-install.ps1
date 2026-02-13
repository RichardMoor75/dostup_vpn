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
$ICON_URL = 'https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/icon.ico'

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

function Get-MixedPort {
    $port = 2080
    if (Test-Path $CONFIG_FILE) {
        try {
            $cfg = Get-Content $CONFIG_FILE -Raw
            if ($cfg -match 'mixed-port:\s*(\d+)') {
                $port = [int]$matches[1]
            }
        } catch { }
    }
    return $port
}

function Test-LocalPortListening($port) {
    try {
        $lines = netstat -ano -p tcp 2>$null
        foreach ($line in $lines) {
            $parts = ($line -replace '^\s+', '') -split '\s+'
            if ($parts.Length -lt 2) { continue }
            $localAddress = $parts[1]
            if ($localAddress -match ':(\d+)$' -and [int]$matches[1] -eq $port) {
                return $true
            }
        }
    } catch { }
    return $false
}

function Wait-MihomoStart($timeoutSec = 5) {
    $proxyPort = Get-MixedPort
    for ($i = 0; $i -lt $timeoutSec; $i++) {
        if (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) {
            return $true
        }
        if (Test-LocalPortListening $proxyPort) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    if (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) {
        return $true
    }
    return (Test-LocalPortListening $proxyPort)
}

function Invoke-DownloadWithRetryJob($url, $output, $maxRetries = 3) {
    if (-not (Get-Command Start-Job -ErrorAction SilentlyContinue)) {
        return $null
    }
    try {
        return Start-Job -ScriptBlock {
            param($url, $output, $maxRetries)
            $ErrorActionPreference = 'Stop'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $retry = 0
            while ($retry -lt $maxRetries) {
                try {
                    Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing
                    if ((Test-Path $output) -and ((Get-Item $output).Length -gt 0)) {
                        return $true
                    }
                } catch { }
                $retry++
                if ($retry -lt $maxRetries) {
                    Start-Sleep -Seconds 2
                }
            }
            return $false
        } -ArgumentList $url, $output, $maxRetries
    } catch {
        return $null
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
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            foreach ($entry in $archive.Entries) {
                $entryPath = Join-Path $destPath $entry.FullName
                $entryDir = Split-Path $entryPath -Parent
                if (-not (Test-Path $entryDir)) {
                    New-Item -ItemType Directory -Path $entryDir -Force | Out-Null
                }
                if ($entry.FullName -notmatch '[\\/]$') {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $entryPath, $true)
                }
            }
        } finally {
            $archive.Dispose()
        }
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
# Use compatible build for older Windows (7/8/8.1)
$osVersion = [Environment]::OSVersion.Version
if ($osVersion.Major -lt 10 -and $arch -eq 'amd64') {
    $filename = "mihomo-windows-$arch-compatible-$version.zip"
    Write-Info "Using compatible build for Windows $($osVersion.Major).$($osVersion.Minor)"
} else {
    $filename = "mihomo-windows-$arch-$version.zip"
}
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

# Remove TUN block for older Windows (7/8/8.1) - TUN driver requires Win 10+
$osVersion = [Environment]::OSVersion.Version
if ($osVersion.Major -lt 10) {
    Write-Step 'Removing TUN mode (not supported on Windows < 10)...'
    $configContent = Get-Content $CONFIG_FILE -Raw
    # Remove entire tun: block (tun: line + all indented lines below it)
    $configContent = $configContent -replace '(?m)^tun:\s*[\r\n]+(?:^[ \t]+[^\r\n]*[\r\n]+)*', ''
    [System.IO.File]::WriteAllText($CONFIG_FILE, $configContent, (New-Object System.Text.UTF8Encoding($false)))
    Write-OK 'TUN removed, using system proxy mode'
}

Write-Step 'Downloading geo databases and icon...'
$geoSuccess = $true
$iconPath = "$DOSTUP_DIR\icon.ico"
$parallelAvailable = ($null -ne (Get-Command Start-Job -ErrorAction SilentlyContinue))

if ($parallelAvailable) {
    $geoIpJob = Invoke-DownloadWithRetryJob $GEOIP_URL "$DOSTUP_DIR\geoip.dat"
    $geoSiteJob = Invoke-DownloadWithRetryJob $GEOSITE_URL "$DOSTUP_DIR\geosite.dat"
    $iconJob = Invoke-DownloadWithRetryJob $ICON_URL $iconPath

    if ($geoIpJob -and $geoSiteJob -and $iconJob) {
        Wait-Job -Job @($geoIpJob, $geoSiteJob, $iconJob) | Out-Null
        $geoIpOk = [bool](Receive-Job $geoIpJob -ErrorAction SilentlyContinue | Select-Object -Last 1)
        $geoSiteOk = [bool](Receive-Job $geoSiteJob -ErrorAction SilentlyContinue | Select-Object -Last 1)
        $iconOk = [bool](Receive-Job $iconJob -ErrorAction SilentlyContinue | Select-Object -Last 1)
        Remove-Job -Job @($geoIpJob, $geoSiteJob, $iconJob) -Force -ErrorAction SilentlyContinue

        if (-not $geoIpOk) { Write-Fail 'Failed to download geoip.dat'; $geoSuccess = $false }
        if (-not $geoSiteOk) { Write-Fail 'Failed to download geosite.dat'; $geoSuccess = $false }
        if ($geoSuccess) { Write-OK 'Geo databases downloaded' }
        if ($iconOk) { Write-OK 'Icon downloaded' } else { Write-Fail 'Icon download failed (shortcut will use default icon)' }
    } else {
        if ($geoIpJob) { Remove-Job $geoIpJob -Force -ErrorAction SilentlyContinue }
        if ($geoSiteJob) { Remove-Job $geoSiteJob -Force -ErrorAction SilentlyContinue }
        if ($iconJob) { Remove-Job $iconJob -Force -ErrorAction SilentlyContinue }
        $parallelAvailable = $false
    }
}

if (-not $parallelAvailable) {
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
    if (Invoke-DownloadWithRetry $ICON_URL $iconPath) {
        Write-OK 'Icon downloaded'
    } else {
        Write-Fail 'Icon download failed (shortcut will use default icon)'
    }
}

$settings = @{
    subscription_url = $subUrl
    installed_version = $version
}
if ($geoSuccess) {
    $settings.last_geo_update = (Get-Date -Format 'yyyy-MM-dd')
}
# Write JSON without BOM for old PowerShell compatibility
$settingsJson = $settings | ConvertTo-Json
[System.IO.File]::WriteAllText($SETTINGS_FILE, $settingsJson, (New-Object System.Text.UTF8Encoding($false)))

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
    $sitesJson = $sitesContent | ConvertTo-Json
    [System.IO.File]::WriteAllText($sitesFile, $sitesJson, (New-Object System.Text.UTF8Encoding($false)))
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
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            foreach ($entry in $archive.Entries) {
                $entryPath = Join-Path $destPath $entry.FullName
                $entryDir = Split-Path $entryPath -Parent
                if (-not (Test-Path $entryDir)) {
                    New-Item -ItemType Directory -Path $entryDir -Force | Out-Null
                }
                if ($entry.FullName -notmatch '[\\/]$') {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $entryPath, $true)
                }
            }
        } finally {
            $archive.Dispose()
        }
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

function Test-MihomoChecksum($version, $filename, $archivePath) {
    $checksumUrl = "https://github.com/MetaCubeX/mihomo/releases/download/$version/$filename.sha256"
    try {
        $expectedHash = (Invoke-WebRequest -Uri $checksumUrl -UseBasicParsing -ErrorAction Stop).Content.Trim().Split()[0]
        if ($expectedHash -match '^[a-fA-F0-9]{64}$') {
            $actualHash = Get-FileSHA256 $archivePath
            return ($expectedHash.ToUpper() -eq $actualHash.ToUpper())
        }
        Write-Info 'SHA256 не найден, пропуск проверки'
        return $true
    } catch {
        Write-Info 'SHA256 не найден, пропуск проверки'
        return $true
    }
}

function Get-ProxyPort {
    $port = 2080
    if (Test-Path $CONFIG_FILE) {
        $cfg = Get-Content $CONFIG_FILE -Raw
        if ($cfg -match 'mixed-port:\s*(\d+)') { $port = $matches[1] }
    }
    return $port
}

function Test-LocalPortListening($port) {
    try {
        $lines = netstat -ano -p tcp 2>$null
        foreach ($line in $lines) {
            $parts = ($line -replace '^\s+', '') -split '\s+'
            if ($parts.Length -lt 2) { continue }
            $localAddress = $parts[1]
            if ($localAddress -match ':(\d+)$' -and [int]$matches[1] -eq $port) {
                return $true
            }
        }
    } catch { }
    return $false
}

function Wait-MihomoStart($timeoutSec = 5) {
    $proxyPort = Get-ProxyPort
    for ($i = 0; $i -lt $timeoutSec; $i++) {
        if (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) {
            return $true
        }
        if (Test-LocalPortListening $proxyPort) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    if (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) {
        return $true
    }
    return (Test-LocalPortListening $proxyPort)
}

function Enable-SystemProxy {
    $osVer = [Environment]::OSVersion.Version
    if ($osVer.Major -lt 10) {
        $port = Get-ProxyPort
        $proxy = "127.0.0.1:$port"
        $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        Set-ItemProperty -Path $reg -Name ProxyEnable -Value 1
        Set-ItemProperty -Path $reg -Name ProxyServer -Value $proxy
        Write-OK "Системный прокси включён: $proxy"
    }
}

function Disable-SystemProxy {
    $osVer = [Environment]::OSVersion.Version
    if ($osVer.Major -lt 10) {
        $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        Set-ItemProperty -Path $reg -Name ProxyEnable -Value 0
        Write-OK 'Системный прокси отключён'
    }
}

function Update-Providers {
    Write-Host ''
    Write-Step 'Обновление провайдеров...'
    Write-Host ''

    $api = 'http://127.0.0.1:9090'
    $endpoints = @(
        @{ Name = 'Прокси (Subscription)'; Url = "$api/providers/proxies/Subscription" },
        @{ Name = 'Правила (direct-rules)'; Url = "$api/providers/rules/direct-rules" },
        @{ Name = 'Правила (proxy-rules)'; Url = "$api/providers/rules/proxy-rules" }
    )

    foreach ($ep in $endpoints) {
        try {
            Invoke-WebRequest -Uri $ep.Url -Method Put -UseBasicParsing -ErrorAction Stop | Out-Null
            Write-OK "$($ep.Name) — обновлено"
        } catch {
            Write-Fail "$($ep.Name) — ошибка: $_"
        }
    }

    Write-Host ''
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

    # Use proxy for Windows < 10 (TUN not available)
    $useProxy = $false
    $proxyUrl = $null
    $osVer = [Environment]::OSVersion.Version
    if ($osVer.Major -lt 10) {
        $port = Get-ProxyPort
        $proxyUrl = "http://127.0.0.1:$port"
        $useProxy = $true
        Write-Info "Проверка через прокси $proxyUrl"
    }

    foreach ($site in $sites) {
        try {
            if ($useProxy) {
                $null = Invoke-WebRequest -Uri "https://$site" -Method Head -TimeoutSec 10 -UseBasicParsing -Proxy $proxyUrl -ErrorAction Stop
            } else {
                $null = Invoke-WebRequest -Uri "https://$site" -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            }
            Write-Host "[OK] $site — доступен" -ForegroundColor Green
        } catch {
            Write-Host "[X] $site — недоступен" -ForegroundColor Red
        }
    }

    Write-Host ''
}

function Stop-Mihomo {
    Write-Step 'Остановка Mihomo (требуются права администратора)...'
    Start-Process -FilePath 'taskkill' -ArgumentList '/F /IM mihomo.exe' -Verb RunAs -Wait -WindowStyle Hidden
    # Wait with timeout
    $stopTimeout = 10
    while ((Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) -and $stopTimeout -gt 0) {
        Start-Sleep -Seconds 1
        $stopTimeout--
    }
    $proc = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
    if (-not $proc) {
        Disable-SystemProxy
        Write-OK 'Mihomo остановлен'
        return $true
    } else {
        Write-Fail 'Не удалось остановить. Попробуйте перезагрузить компьютер.'
        return $false
    }
}

function Save-Settings($s) {
    # Write JSON without BOM (old PowerShell adds BOM with Set-Content -Encoding UTF8)
    $json = $s | ConvertTo-Json
    [System.IO.File]::WriteAllText($SETTINGS_FILE, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Start-Mihomo {
    # Read settings with fallback
    $settings = $null
    try {
        $content = Get-Content $SETTINGS_FILE -Raw -ErrorAction Stop
        $settings = $content | ConvertFrom-Json
    } catch {
        Write-Info 'Не удалось прочитать настройки'
        $settings = @{ subscription_url = ''; installed_version = '' }
    }

    Write-Step 'Проверка обновлений ядра...'
    try {
        $headers = @{ 'User-Agent' = 'Dostup-Installer' }
        $rel = Invoke-RestMethod -Uri $MIHOMO_API -Headers $headers
        $latest = $rel.tag_name
        if ($settings.installed_version -ne $latest) {
            Write-Step "Обновление: $($settings.installed_version) → $latest"
            $arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { '386' }
            if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
            # Use compatible build for older Windows (7/8/8.1)
            $osVer = [Environment]::OSVersion.Version
            if ($osVer.Major -lt 10 -and $arch -eq 'amd64') {
                $fn = "mihomo-windows-$arch-compatible-$latest.zip"
            } else {
                $fn = "mihomo-windows-$arch-$latest.zip"
            }
            $url = "https://github.com/MetaCubeX/mihomo/releases/download/$latest/$fn"
            if (Invoke-DownloadWithRetry $url "$DOSTUP_DIR\m.zip") {
                if (Test-MihomoChecksum $latest $fn "$DOSTUP_DIR\m.zip") {
                    Expand-ZipFile "$DOSTUP_DIR\m.zip" $DOSTUP_DIR
                    Remove-Item "$DOSTUP_DIR\m.zip" -Force
                    $exe = Get-ChildItem -Path $DOSTUP_DIR -Filter 'mihomo*.exe' | Select-Object -First 1
                    if ($exe -and $exe.Name -ne 'mihomo.exe') {
                        Remove-Item $MIHOMO_BIN -Force -ErrorAction SilentlyContinue
                        Rename-Item -Path $exe.FullName -NewName 'mihomo.exe' -Force
                    }
                    $settings.installed_version = $latest
                    Save-Settings $settings
                    Write-OK 'Ядро обновлено'
                } else {
                    Remove-Item "$DOSTUP_DIR\m.zip" -Force -ErrorAction SilentlyContinue
                    Write-Fail 'Ошибка проверки хэша, используем текущую версию'
                }
            } else { Write-Fail 'Не удалось обновить, используем текущую версию' }
        } else { Write-OK 'Ядро актуально' }
    } catch { Write-OK 'Ядро актуально' }

    Write-Step 'Скачивание конфига...'
    if (Test-Path $CONFIG_FILE) { Copy-Item $CONFIG_FILE "$CONFIG_FILE.backup" -Force }
    $tempCfg = "$CONFIG_FILE.tmp"
    if (Invoke-DownloadWithRetry $settings.subscription_url $tempCfg) {
        if (Test-ValidYaml $tempCfg) {
            Move-Item $tempCfg $CONFIG_FILE -Force
            # Remove TUN block for older Windows
            $osVer = [Environment]::OSVersion.Version
            if ($osVer.Major -lt 10) {
                $cfgContent = Get-Content $CONFIG_FILE -Raw
                $cfgContent = $cfgContent -replace '(?m)^tun:\s*[\r\n]+(?:^[ \t]+[^\r\n]*[\r\n]+)*', ''
                [System.IO.File]::WriteAllText($CONFIG_FILE, $cfgContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            Write-OK 'Конфиг обновлён'
        } else {
            Write-Fail 'Невалидный YAML, используем старый конфиг'
            Remove-Item $tempCfg -Force -ErrorAction SilentlyContinue
            if (Test-Path "$CONFIG_FILE.backup") { Move-Item "$CONFIG_FILE.backup" $CONFIG_FILE -Force }
        }
    } else {
        Write-Fail 'Используем старый конфиг'
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
        Write-Step 'Обновление geo-баз...'
        $geoOk = $true
        if (-not (Invoke-DownloadWithRetry $GEOIP_URL "$DOSTUP_DIR\geoip.dat")) { $geoOk = $false }
        if (-not (Invoke-DownloadWithRetry $GEOSITE_URL "$DOSTUP_DIR\geosite.dat")) { $geoOk = $false }
        if ($geoOk) {
            $settings.last_geo_update = (Get-Date -Format 'yyyy-MM-dd')
            Save-Settings $settings
            Write-OK 'Geo-базы обновлены'
        }
    }

    Write-Step 'Запуск Mihomo...'
    Write-Host ''
    Start-Process cmd.exe -ArgumentList "/c `"`"$MIHOMO_BIN`" -d `"$DOSTUP_DIR`" > `"$DOSTUP_DIR\logs\mihomo.log`" 2>&1`"" -Verb RunAs -WindowStyle Hidden
    if (Wait-MihomoStart 5) {
        Enable-SystemProxy
        Write-Host ''
        Write-Host '============================================' -ForegroundColor Green
        Write-Host '[OK] Mihomo успешно запущен!' -ForegroundColor Green
        Write-Host '============================================' -ForegroundColor Green
        Write-Host ''
        Write-Host 'Панель: https://metacubex.github.io/metacubexd/'
        Write-Host 'API: 127.0.0.1:9090'
        return $true
    } else {
        Write-Fail 'Не удалось запустить'
        Write-Host "Логи: $DOSTUP_DIR\logs"
        return $false
    }
}

# === MAIN ===

Write-Host ''
Write-Host '=== Dostup VPN ===' -ForegroundColor Blue
Write-Host ''

$proc = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
if ($proc) {
    # Mihomo запущен — показываем меню
    Write-Host 'Mihomo работает' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Панель: https://metacubex.github.io/metacubexd/'
    Write-Host 'API: 127.0.0.1:9090'
    Write-Host ''
    Write-Host '1) Остановить'
    Write-Host '2) Перезапустить'
    Write-Host '3) Обновить прокси и правила'
    Write-Host '4) Проверить доступ'
    Write-Host '5) Отмена'
    Write-Host ''
    $choice = Read-Host 'Выберите (1-5)'

    switch ($choice) {
        '1' {
            Stop-Mihomo
            Write-Host ''
            Write-Host 'Окно закроется через 3 секунды...'
            Start-Sleep -Seconds 3
        }
        '2' {
            Stop-Mihomo
            Write-Host ''
            Start-Mihomo
            Write-Host ''
            Write-Host 'Окно закроется через 5 секунд...'
            Start-Sleep -Seconds 5
        }
        '3' {
            Update-Providers
            Read-Host 'Нажмите Enter для закрытия'
        }
        '4' {
            Test-SiteAccess
            Read-Host 'Нажмите Enter для закрытия'
        }
        default {
            Write-Host ''
            Write-Host 'Отменено'
            Write-Host ''
            Write-Host 'Окно закроется через 2 секунды...'
            Start-Sleep -Seconds 2
        }
    }
} else {
    # Mihomo не запущен — запускаем
    Start-Mihomo
    Write-Host ''
    Write-Host 'Окно закроется через 5 секунд...'
    Start-Sleep -Seconds 5
}
'@
$controlPs1 | Set-Content -Path "$DOSTUP_DIR\Dostup_VPN.ps1" -Encoding UTF8

# Remove old scripts if exist
Remove-Item "$DOSTUP_DIR\dostup-start.ps1" -Force -ErrorAction SilentlyContinue
Remove-Item "$DOSTUP_DIR\dostup-stop.ps1" -Force -ErrorAction SilentlyContinue

Write-OK 'Control script created'

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
Start-Process cmd.exe -ArgumentList "/c `"`"$MIHOMO_BIN`" -d `"$DOSTUP_DIR`" > `"$LOGS_DIR\mihomo.log`" 2>&1`"" -Verb RunAs -WindowStyle Hidden
if (Wait-MihomoStart 5) {
    # Enable system proxy for Windows < 10
    $osVersion = [Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        $proxyPort = 2080
        $cfgContent = Get-Content $CONFIG_FILE -Raw
        if ($cfgContent -match 'mixed-port:\s*(\d+)') { $proxyPort = $matches[1] }
        $proxyServer = "127.0.0.1:$proxyPort"
        $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
        Set-ItemProperty -Path $regPath -Name ProxyServer -Value $proxyServer
        Write-OK "System proxy enabled: $proxyServer"
    }
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
