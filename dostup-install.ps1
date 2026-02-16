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
$ICON_ON_URL = 'https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/icon_on.png'
$ICON_OFF_URL = 'https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/icon_off.png'

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
                    Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing -TimeoutSec 30
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
            Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing -TimeoutSec 30
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
    # Stop via service (if installed)
    sc.exe stop DostupVPN 2>$null | Out-Null
    Start-Sleep -Seconds 2
    # Non-elevated kill (for Win 7/8 process mode)
    Stop-Process -Name mihomo -Force -ErrorAction SilentlyContinue
    # Fallback: elevated taskkill (for older installations with elevated mihomo)
    if (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) {
        Start-Process -FilePath 'taskkill' -ArgumentList '/F /IM mihomo.exe' -Verb RunAs -Wait -WindowStyle Hidden
    }
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

# Kill existing tray process if running
$trayProcs = Get-WmiObject Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'DostupVPN-Tray\.ps1' }
if ($trayProcs) {
    Write-Step 'Stopping tray application...'
    $trayProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    Write-OK 'Tray application stopped'
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
    $release = Invoke-RestMethod -Uri $MIHOMO_API -Headers $headers -TimeoutSec 15
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
    $expectedHash = (Invoke-WebRequest -Uri $checksumUrl -UseBasicParsing -ErrorAction Stop -TimeoutSec 15).Content.Trim().Split()[0]
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

Write-Step 'Downloading geo databases and icons...'
$geoSuccess = $true
$iconPath = "$DOSTUP_DIR\icon.ico"
$iconOnPath = "$DOSTUP_DIR\icon_on.png"
$iconOffPath = "$DOSTUP_DIR\icon_off.png"
$parallelAvailable = ($null -ne (Get-Command Start-Job -ErrorAction SilentlyContinue))

if ($parallelAvailable) {
    $geoIpJob = Invoke-DownloadWithRetryJob $GEOIP_URL "$DOSTUP_DIR\geoip.dat"
    $geoSiteJob = Invoke-DownloadWithRetryJob $GEOSITE_URL "$DOSTUP_DIR\geosite.dat"
    $iconJob = Invoke-DownloadWithRetryJob $ICON_URL $iconPath
    $iconOnJob = Invoke-DownloadWithRetryJob $ICON_ON_URL $iconOnPath
    $iconOffJob = Invoke-DownloadWithRetryJob $ICON_OFF_URL $iconOffPath

    $allJobs = @($geoIpJob, $geoSiteJob, $iconJob, $iconOnJob, $iconOffJob) | Where-Object { $_ -ne $null }
    if ($allJobs.Count -eq 5) {
        Wait-Job -Job $allJobs | Out-Null
        $geoIpOk = [bool](Receive-Job $geoIpJob -ErrorAction SilentlyContinue | Select-Object -Last 1)
        $geoSiteOk = [bool](Receive-Job $geoSiteJob -ErrorAction SilentlyContinue | Select-Object -Last 1)
        $iconOk = [bool](Receive-Job $iconJob -ErrorAction SilentlyContinue | Select-Object -Last 1)
        $iconOnOk = [bool](Receive-Job $iconOnJob -ErrorAction SilentlyContinue | Select-Object -Last 1)
        $iconOffOk = [bool](Receive-Job $iconOffJob -ErrorAction SilentlyContinue | Select-Object -Last 1)
        Remove-Job -Job $allJobs -Force -ErrorAction SilentlyContinue

        if (-not $geoIpOk) { Write-Fail 'Failed to download geoip.dat'; $geoSuccess = $false }
        if (-not $geoSiteOk) { Write-Fail 'Failed to download geosite.dat'; $geoSuccess = $false }
        if ($geoSuccess) { Write-OK 'Geo databases downloaded' }
        if ($iconOk) { Write-OK 'Icon downloaded' } else { Write-Fail 'Icon download failed (shortcut will use default icon)' }
        if ($iconOnOk -and $iconOffOk) { Write-OK 'Tray icons downloaded' } else { Write-Info 'Tray icons download failed (will use fallback icon)' }
    } else {
        foreach ($j in $allJobs) { Remove-Job $j -Force -ErrorAction SilentlyContinue }
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
    # Tray icons (non-fatal)
    if (Invoke-DownloadWithRetry $ICON_ON_URL $iconOnPath) {
        if (Invoke-DownloadWithRetry $ICON_OFF_URL $iconOffPath) {
            Write-OK 'Tray icons downloaded'
        } else { Write-Info 'Tray icon_off download failed (will use fallback)' }
    } else { Write-Info 'Tray icon_on download failed (will use fallback)' }
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

# Save installer hash for self-update
try {
    $installerContent = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.ps1' -UseBasicParsing -TimeoutSec 10).Content
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($installerContent)
    $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLower()
    $settings.installer_hash = $hash
    $settingsJson = $settings | ConvertTo-Json
    [System.IO.File]::WriteAllText($SETTINGS_FILE, $settingsJson, (New-Object System.Text.UTF8Encoding($false)))
} catch {}

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
            Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing -TimeoutSec 30
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
        $expectedHash = (Invoke-WebRequest -Uri $checksumUrl -UseBasicParsing -ErrorAction Stop -TimeoutSec 15).Content.Trim().Split()[0]
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
        if ($cfg -match 'mixed-port:\s*(\d+)') { $port = [int]$matches[1] }
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

function Test-ServiceMode {
    # Returns $true if the DostupVPN service is installed (regardless of running state)
    $null = sc.exe query DostupVPN 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Update-Providers {
    Write-Host ''
    Write-Step 'Обновление провайдеров...'
    Write-Host ''

    $api = 'http://127.0.0.1:9090'

    # Динамическое получение proxy-providers
    try {
        $proxyData = Invoke-WebRequest -Uri "$api/providers/proxies" -UseBasicParsing -TimeoutSec 5 | ConvertFrom-Json
        foreach ($name in $proxyData.providers.PSObject.Properties.Name) {
            if ($name -eq 'default') { continue }
            try {
                Invoke-WebRequest -Uri "$api/providers/proxies/$name" -Method Put -UseBasicParsing -ErrorAction Stop -TimeoutSec 15 | Out-Null
                Write-OK "Прокси ($name) — обновлено"
            } catch {
                Write-Fail "Прокси ($name) — ошибка: $_"
            }
        }
    } catch {
        Write-Fail "Не удалось получить список proxy-providers: $_"
    }

    # Динамическое получение rule-providers
    try {
        $ruleData = Invoke-WebRequest -Uri "$api/providers/rules" -UseBasicParsing -TimeoutSec 5 | ConvertFrom-Json
        foreach ($name in $ruleData.providers.PSObject.Properties.Name) {
            try {
                Invoke-WebRequest -Uri "$api/providers/rules/$name" -Method Put -UseBasicParsing -ErrorAction Stop -TimeoutSec 15 | Out-Null
                Write-OK "Правило ($name) — обновлено"
            } catch {
                Write-Fail "Правило ($name) — ошибка: $_"
            }
        }
    } catch {
        Write-Fail "Не удалось получить список rule-providers: $_"
    }

    Write-Host ''
}

function Invoke-Healthcheck {
    Write-Host ''
    Write-Step 'Проверка нод...'
    Write-Host ''

    $api = 'http://127.0.0.1:9090'

    try {
        $proxyData = Invoke-WebRequest -Uri "$api/providers/proxies" -UseBasicParsing -TimeoutSec 5 | ConvertFrom-Json
        foreach ($name in $proxyData.providers.PSObject.Properties.Name) {
            if ($name -eq 'default') { continue }
            # Run healthcheck
            try {
                Invoke-WebRequest -Uri "$api/providers/proxies/$name/healthcheck" -UseBasicParsing -ErrorAction Stop -TimeoutSec 30 | Out-Null
            } catch {
                Write-Fail "$name — ошибка healthcheck: $_"
                continue
            }

            # Get detailed results
            Write-Host "[$name]" -ForegroundColor Cyan
            try {
                $details = Invoke-WebRequest -Uri "$api/providers/proxies/$name" -UseBasicParsing -TimeoutSec 5 | ConvertFrom-Json
                $alive = 0
                $total = 0
                $totalDelay = 0
                foreach ($proxy in $details.proxies) {
                    $total++
                    $history = $proxy.history
                    $delay = 0
                    if ($history -and $history.Count -gt 0) {
                        $delay = $history[-1].delay
                    }
                    if ($delay -gt 0) {
                        $alive++
                        $totalDelay += $delay
                        Write-Host "  [OK] $($proxy.name) — ${delay}ms" -ForegroundColor Green
                    } else {
                        Write-Host "  [FAIL] $($proxy.name) — мёртв" -ForegroundColor Red
                    }
                }
                $avg = if ($alive -gt 0) { [math]::Round($totalDelay / $alive) } else { 0 }
                if ($alive -gt 0) {
                    Write-Host "  Итого: $alive/$total нод (avg ${avg}ms)" -ForegroundColor Yellow
                } else {
                    Write-Host "  Итого: 0/$total нод" -ForegroundColor Red
                }
            } catch {
                Write-Fail "  Не удалось получить данные: $_"
            }
            Write-Host ''
        }
    } catch {
        Write-Fail "Не удалось получить список провайдеров: $_"
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
    if (Test-ServiceMode) {
        Write-Step 'Остановка Mihomo...'
        sc.exe stop DostupVPN 2>$null | Out-Null
    } elseif ([Environment]::OSVersion.Version.Major -lt 10) {
        Write-Step 'Остановка Mihomo...'
        Stop-Process -Name mihomo -Force -ErrorAction SilentlyContinue
    } else {
        Write-Step 'Остановка Mihomo (требуются права администратора)...'
        Start-Process cmd.exe -ArgumentList "/c taskkill /F /IM mihomo.exe & powershell -ExecutionPolicy Bypass -NoProfile -File `"$DOSTUP_DIR\dns-helper.ps1`" restore" -Verb RunAs -Wait -WindowStyle Hidden
    }
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

function Test-InstallerUpdate {
    try {
        $s = Get-Content $SETTINGS_FILE -Raw | ConvertFrom-Json
        if (-not $s.installer_hash) { return }

        $url = 'https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.ps1'
        # Retry: сеть может быть не готова сразу после остановки VPN
        $content = $null
        for ($retry = 0; $retry -lt 3; $retry++) {
            try {
                $content = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15).Content
                break
            } catch {
                if ($retry -lt 2) { Start-Sleep -Seconds 2 }
            }
        }
        if (-not $content) { return }

        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        $newHash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLower()

        if ($newHash -ne $s.installer_hash) {
            if ($env:DOSTUP_SILENT -eq '1') {
                Write-Output 'DOSTUP_SCRIPT_UPDATE'
                return
            }
            Write-Host ''
            Write-Warning 'Доступно обновление скрипта управления'
            $choice = Read-Host '  Обновить сейчас? (y/N)'
            if ($choice -eq 'y' -or $choice -eq 'Y') {
                Write-Step 'Обновление...'
                $tmp = "$env:TEMP\dostup-install-update.ps1"
                [System.IO.File]::WriteAllText($tmp, $content, (New-Object System.Text.UTF8Encoding($false)))
                & powershell -ExecutionPolicy Bypass -File $tmp
                exit
            }
        }
    } catch {}
}

function Start-Mihomo {
    Test-InstallerUpdate
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
        $rel = Invoke-RestMethod -Uri $MIHOMO_API -Headers $headers -TimeoutSec 15
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
    if (Test-ServiceMode) {
        sc.exe start DostupVPN 2>$null | Out-Null
    } elseif ([Environment]::OSVersion.Version.Major -lt 10) {
        Start-Process cmd.exe -ArgumentList "/c `"`"$MIHOMO_BIN`" -d `"$DOSTUP_DIR`" > `"$DOSTUP_DIR\logs\mihomo.log`" 2>&1`"" -WindowStyle Hidden
    } else {
        Start-Process cmd.exe -ArgumentList "/c powershell -ExecutionPolicy Bypass -NoProfile -File `"$DOSTUP_DIR\dns-helper.ps1`" set & `"`"$MIHOMO_BIN`" -d `"$DOSTUP_DIR`" > `"$DOSTUP_DIR\logs\mihomo.log`" 2>&1`"" -Verb RunAs -WindowStyle Hidden
    }
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

# CLI mode (called from tray app or other scripts)
if ($args.Count -gt 0) {
    switch ($args[0]) {
        'start' {
            Start-Mihomo
            exit
        }
        'stop' {
            Stop-Mihomo
            exit
        }
        'restart' {
            Stop-Mihomo
            Write-Host ''
            Start-Mihomo
            Write-Host ''
            Write-Host 'Окно закроется через 5 секунд...'
            Start-Sleep -Seconds 5
            exit
        }
        'restart-silent' {
            $env:DOSTUP_SILENT = '1'
            Stop-Mihomo *>&1 | Out-Null
            $output = Start-Mihomo *>&1 | Out-String
            $summary = @()
            if ($output -match 'DOSTUP_SCRIPT_UPDATE') { $summary += 'Обновление скрипта доступно' }
            if ($output -match 'Ядро обновлено') { $summary += 'Ядро обновлено' }
            if ($output -match 'Конфиг обновлён') { $summary += 'Конфиг обновлён' }
            if ($output -match 'Geo-базы обновлены') { $summary += 'Geo-базы обновлены' }
            if (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue) {
                $summary += 'VPN перезапущен'
            } else {
                $summary = @('Ошибка перезапуска')
            }
            $result = $summary -join "`n"
            [System.IO.File]::WriteAllText("$DOSTUP_DIR\restart-result.txt", $result, (New-Object System.Text.UTF8Encoding($false)))
            exit
        }
        'check' {
            Test-SiteAccess
            Read-Host 'Нажмите Enter для закрытия'
            exit
        }
        'update-providers' {
            Update-Providers
            exit
        }
        'healthcheck' {
            Invoke-Healthcheck
            exit
        }
        'dns-set' {
            if ([Environment]::OSVersion.Version.Major -ge 10) {
                & "$DOSTUP_DIR\dns-helper.ps1" set
            }
            exit
        }
    }
}

# DNS fail-safe check (Win 10+ only)
if ([Environment]::OSVersion.Version.Major -ge 10) {
    $dnsHelper = "$DOSTUP_DIR\dns-helper.ps1"
    $dnsFile = "$DOSTUP_DIR\original_dns.json"
    $miRunning = Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue
    if ($miRunning -and -not (Test-Path $dnsFile)) {
        # Mihomo running but DNS not set — set it (e.g. after update)
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$dnsHelper`" set" -Verb RunAs -Wait -WindowStyle Hidden
    } elseif (-not $miRunning -and (Test-Path $dnsFile)) {
        # Mihomo not running but DNS file exists — crash recovery
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$dnsHelper`" restore" -Verb RunAs -Wait -WindowStyle Hidden
    }
}

# Interactive mode (desktop shortcut)
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
    Write-Host '4) Проверка нод'
    Write-Host '5) Проверить доступ'
    Write-Host '6) Отмена'
    Write-Host ''
    $choice = Read-Host 'Выберите (1-6)'

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
            Invoke-Healthcheck
            Read-Host 'Нажмите Enter для закрытия'
        }
        '5' {
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
    # Запускаем tray если установлен но не запущен
    $trayVbs = "$DOSTUP_DIR\LaunchTray.vbs"
    if (Test-Path $trayVbs) {
        $trayRunning = Get-WmiObject Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'DostupVPN-Tray\.ps1' }
        if (-not $trayRunning) {
            Start-Process wscript.exe -ArgumentList "`"$trayVbs`"" -WindowStyle Hidden
        }
    }
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

Write-Step 'Creating tray application...'

$trayPs1 = @'
# DostupVPN Tray Application
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# DPI awareness + hide console window
Add-Type -Name Win32 -Namespace Native -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
"@
[Native.Win32]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()
$consolePtr = [Native.Win32]::GetConsoleWindow()
[Native.Win32]::ShowWindow($consolePtr, 0) | Out-Null

# Single instance via mutex
$mutexName = 'Global\DostupVPN-Tray'
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    exit
}

$DOSTUP_DIR = "$env:USERPROFILE\dostup"
$CONTROL_SCRIPT = "$DOSTUP_DIR\Dostup_VPN.ps1"
$MIHOMO_BIN = "$DOSTUP_DIR\mihomo.exe"
$CONFIG_FILE = "$DOSTUP_DIR\config.yaml"

# Load icon from PNG file
function ConvertTo-Icon($pngPath) {
    try {
        if (Test-Path $pngPath) {
            $bmp = New-Object System.Drawing.Bitmap($pngPath)
            $hIcon = $bmp.GetHicon()
            $bmp.Dispose()
            $icon = [System.Drawing.Icon]::FromHandle($hIcon)
            return $icon
        }
    } catch { }
    return $null
}

$iconOn = ConvertTo-Icon "$DOSTUP_DIR\icon_on.png"
$iconOff = ConvertTo-Icon "$DOSTUP_DIR\icon_off.png"

# Fallback to icon.ico
$icoPath = "$DOSTUP_DIR\icon.ico"
if ((-not $iconOn) -and (Test-Path $icoPath)) {
    try { $iconOn = New-Object System.Drawing.Icon($icoPath) } catch { }
}
if ((-not $iconOff) -and (Test-Path $icoPath)) {
    try { $iconOff = New-Object System.Drawing.Icon($icoPath) } catch { }
}

# Ultimate fallback
if (-not $iconOn) { $iconOn = [System.Drawing.SystemIcons]::Application }
if (-not $iconOff) { $iconOff = [System.Drawing.SystemIcons]::Application }

# Create NotifyIcon
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Visible = $true
$tray.Text = 'Dostup VPN'

# Context menu
$cms = New-Object System.Windows.Forms.ContextMenuStrip
$cms.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$boldFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

$miStatus = New-Object System.Windows.Forms.ToolStripMenuItem
$miStatus.Enabled = $false
$miStatus.Font = $boldFont

$sep1 = New-Object System.Windows.Forms.ToolStripSeparator

$miToggle = New-Object System.Windows.Forms.ToolStripMenuItem
$miToggle.Font = $boldFont

$miRestart = New-Object System.Windows.Forms.ToolStripMenuItem
$miRestart.Text = [char]0x21BB + ' Перезапустить'

$sep2 = New-Object System.Windows.Forms.ToolStripSeparator

$miUpdate = New-Object System.Windows.Forms.ToolStripMenuItem
$miUpdate.Text = 'Обновить прокси и правила'

$miHealthcheck = New-Object System.Windows.Forms.ToolStripMenuItem
$miHealthcheck.Text = 'Проверка нод'

$miCheck = New-Object System.Windows.Forms.ToolStripMenuItem
$miCheck.Text = 'Проверить доступ'

[void]$cms.Items.Add($miStatus)
[void]$cms.Items.Add($sep1)
[void]$cms.Items.Add($miToggle)
[void]$cms.Items.Add($miRestart)
[void]$cms.Items.Add($sep2)
[void]$cms.Items.Add($miUpdate)
[void]$cms.Items.Add($miHealthcheck)
[void]$cms.Items.Add($miCheck)

$sep3 = New-Object System.Windows.Forms.ToolStripSeparator
$miExit = New-Object System.Windows.Forms.ToolStripMenuItem
$miExit.Text = 'Выход'

[void]$cms.Items.Add($sep3)
[void]$cms.Items.Add($miExit)

$tray.ContextMenuStrip = $cms

# Helper: get proxy port from config
function Get-ProxyPort {
    $port = 2080
    if (Test-Path $CONFIG_FILE) {
        try {
            $cfg = Get-Content $CONFIG_FILE -Raw
            if ($cfg -match 'mixed-port:\s*(\d+)') { $port = [int]$matches[1] }
        } catch { }
    }
    return $port
}

function Test-VpnRunning {
    return ($null -ne (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue))
}

function Test-ServiceMode {
    # Returns $true if the DostupVPN service is installed (regardless of running state)
    $null = sc.exe query DostupVPN 2>&1
    return ($LASTEXITCODE -eq 0)
}

# Update UI based on mihomo status
function Update-Status {
    if (Test-VpnRunning) {
        $tray.Icon = $iconOn
        $tray.Text = 'Dostup VPN - работает'
        $miStatus.Text = [char]0x25CF + ' VPN работает'
        $miStatus.ForeColor = [System.Drawing.Color]::Green
        $miToggle.Text = 'Остановить VPN'
        $miRestart.Enabled = $true
        $miUpdate.Enabled = $true
        $miHealthcheck.Enabled = $true
        $miCheck.Enabled = $true
    } else {
        $tray.Icon = $iconOff
        $tray.Text = 'Dostup VPN - остановлен'
        $miStatus.Text = [char]0x25CB + ' VPN остановлен'
        $miStatus.ForeColor = [System.Drawing.Color]::Gray
        $miToggle.Text = 'Запустить VPN'
        $miRestart.Enabled = $false
        $miUpdate.Enabled = $false
        $miHealthcheck.Enabled = $false
        $miCheck.Enabled = $false
    }
}

Update-Status

# Timer for polling status (every 5 seconds)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Status })
$timer.Start()

# Toggle VPN (start/stop inline, no terminal window)
$miToggle.Add_Click({
    if (Test-VpnRunning) {
        try {
            if (Test-ServiceMode) {
                sc.exe stop DostupVPN 2>$null | Out-Null
            } elseif ([Environment]::OSVersion.Version.Major -lt 10) {
                Stop-Process -Name mihomo -Force -ErrorAction SilentlyContinue
            } else {
                Start-Process cmd.exe -ArgumentList "/c taskkill /F /IM mihomo.exe & powershell -ExecutionPolicy Bypass -NoProfile -File `"$DOSTUP_DIR\dns-helper.ps1`" restore" -Verb RunAs -Wait -WindowStyle Hidden
            }
            $osVer = [Environment]::OSVersion.Version
            if ($osVer.Major -lt 10) {
                $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                Set-ItemProperty -Path $reg -Name ProxyEnable -Value 0
            }
            Start-Sleep -Seconds 1
            Update-Status
            $tray.ShowBalloonTip(3000, 'Dostup VPN', 'VPN остановлен', [System.Windows.Forms.ToolTipIcon]::Info)
        } catch {
            $tray.ShowBalloonTip(3000, 'Dostup VPN', 'Ошибка остановки', [System.Windows.Forms.ToolTipIcon]::Error)
        }
    } else {
        try {
            if (Test-ServiceMode) {
                sc.exe start DostupVPN 2>$null | Out-Null
            } elseif ([Environment]::OSVersion.Version.Major -lt 10) {
                Start-Process cmd.exe -ArgumentList "/c `"`"$MIHOMO_BIN`" -d `"$DOSTUP_DIR`" > `"$DOSTUP_DIR\logs\mihomo.log`" 2>&1`"" -WindowStyle Hidden
            } else {
                Start-Process cmd.exe -ArgumentList "/c powershell -ExecutionPolicy Bypass -NoProfile -File `"$DOSTUP_DIR\dns-helper.ps1`" set & `"`"$MIHOMO_BIN`" -d `"$DOSTUP_DIR`" > `"$DOSTUP_DIR\logs\mihomo.log`" 2>&1`"" -Verb RunAs -WindowStyle Hidden
            }
            Start-Sleep -Seconds 3
            $osVer = [Environment]::OSVersion.Version
            if ($osVer.Major -lt 10) {
                $port = Get-ProxyPort
                $proxy = "127.0.0.1:$port"
                $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                Set-ItemProperty -Path $reg -Name ProxyEnable -Value 1
                Set-ItemProperty -Path $reg -Name ProxyServer -Value $proxy
            }
            Update-Status
            $tray.ShowBalloonTip(3000, 'Dostup VPN', 'VPN запущен', [System.Windows.Forms.ToolTipIcon]::Info)
        } catch {
            $tray.ShowBalloonTip(3000, 'Dostup VPN', 'Ошибка запуска', [System.Windows.Forms.ToolTipIcon]::Error)
        }
    }
})

# Restart (silent background process with balloon notification)
$miRestart.Add_Click({
    $miRestart.Enabled = $false
    $miStatus.Text = [char]0x21BB + ' Перезапуск...'
    $miStatus.ForeColor = [System.Drawing.Color]::Orange

    $script:restartResultFile = "$DOSTUP_DIR\restart-result.txt"
    Remove-Item $script:restartResultFile -Force -ErrorAction SilentlyContinue
    $script:restartProc = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$CONTROL_SCRIPT`" restart-silent" -WindowStyle Hidden -PassThru

    $script:restartTimer = New-Object System.Windows.Forms.Timer
    $script:restartTimer.Interval = 2000
    $script:restartTimer.Add_Tick({
        if ($script:restartProc.HasExited) {
            $script:restartTimer.Stop()
            $result = ''
            if (Test-Path $script:restartResultFile) {
                $result = [System.IO.File]::ReadAllText($script:restartResultFile, [System.Text.Encoding]::UTF8).Trim()
                Remove-Item $script:restartResultFile -Force -ErrorAction SilentlyContinue
            }
            if ([string]::IsNullOrEmpty($result)) { $result = 'VPN перезапущен' }
            $icon = if ($result -match 'Ошибка') { [System.Windows.Forms.ToolTipIcon]::Error } else { [System.Windows.Forms.ToolTipIcon]::Info }
            $tray.ShowBalloonTip(5000, 'Dostup VPN', $result, $icon)
            Update-Status
        }
    })
    $script:restartTimer.Start()
})

# Update providers (inline PUT requests, balloon notification)
$miUpdate.Add_Click({
    try {
        $api = 'http://127.0.0.1:9090'
        $errors = 0

        # Dynamic proxy providers
        try {
            $proxyData = Invoke-WebRequest -Uri "$api/providers/proxies" -UseBasicParsing -TimeoutSec 5 | ConvertFrom-Json
            foreach ($name in $proxyData.providers.PSObject.Properties.Name) {
                if ($name -eq 'default') { continue }
                try {
                    Invoke-WebRequest -Uri "$api/providers/proxies/$name" -Method Put -UseBasicParsing -ErrorAction Stop -TimeoutSec 15 | Out-Null
                } catch { $errors++ }
            }
        } catch { $errors++ }

        # Dynamic rule providers
        try {
            $ruleData = Invoke-WebRequest -Uri "$api/providers/rules" -UseBasicParsing -TimeoutSec 5 | ConvertFrom-Json
            foreach ($name in $ruleData.providers.PSObject.Properties.Name) {
                try {
                    Invoke-WebRequest -Uri "$api/providers/rules/$name" -Method Put -UseBasicParsing -ErrorAction Stop -TimeoutSec 15 | Out-Null
                } catch { $errors++ }
            }
        } catch { $errors++ }

        if ($errors -eq 0) {
            $tray.ShowBalloonTip(3000, 'Dostup VPN', 'Провайдеры обновлены', [System.Windows.Forms.ToolTipIcon]::Info)
        } else {
            $tray.ShowBalloonTip(3000, 'Dostup VPN', "Обновлено с ошибками ($errors)", [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    } catch {
        $tray.ShowBalloonTip(3000, 'Dostup VPN', 'Ошибка обновления', [System.Windows.Forms.ToolTipIcon]::Error)
    }
})

# Healthcheck (inline, balloon notification)
$miHealthcheck.Add_Click({
    try {
        $api = 'http://127.0.0.1:9090'
        $proxyData = Invoke-WebRequest -Uri "$api/providers/proxies" -UseBasicParsing -TimeoutSec 5 | ConvertFrom-Json
        $summaryLines = @()
        $hasErrors = $false
        foreach ($name in $proxyData.providers.PSObject.Properties.Name) {
            if ($name -eq 'default') { continue }
            try {
                Invoke-WebRequest -Uri "$api/providers/proxies/$name/healthcheck" -UseBasicParsing -ErrorAction Stop -TimeoutSec 30 | Out-Null
            } catch { $hasErrors = $true; continue }

            try {
                $details = Invoke-WebRequest -Uri "$api/providers/proxies/$name" -UseBasicParsing -TimeoutSec 5 | ConvertFrom-Json
                $alive = 0; $total = 0; $totalDelay = 0
                foreach ($proxy in $details.proxies) {
                    $total++
                    $delay = 0
                    if ($proxy.history -and $proxy.history.Count -gt 0) {
                        $delay = $proxy.history[-1].delay
                    }
                    if ($delay -gt 0) { $alive++; $totalDelay += $delay }
                }
                $avg = if ($alive -gt 0) { [math]::Round($totalDelay / $alive) } else { 0 }
                if ($alive -gt 0) {
                    $summaryLines += "${name}: ${alive}/${total} (avg ${avg}ms)"
                } else {
                    $summaryLines += "${name}: 0/${total}"
                    $hasErrors = $true
                }
            } catch { $summaryLines += "${name}: ошибка"; $hasErrors = $true }
        }
        $msg = $summaryLines -join "`n"
        $icon = if ($hasErrors) { [System.Windows.Forms.ToolTipIcon]::Warning } else { [System.Windows.Forms.ToolTipIcon]::Info }
        $tray.ShowBalloonTip(5000, 'Проверка нод', $msg, $icon)
    } catch {
        $tray.ShowBalloonTip(3000, 'Dostup VPN', 'Ошибка проверки нод', [System.Windows.Forms.ToolTipIcon]::Error)
    }
})

# Check access (opens terminal)
$miCheck.Add_Click({
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$CONTROL_SCRIPT`" check"
})

# Exit (stop VPN + close tray)
$miExit.Add_Click({
    if (Test-VpnRunning) {
        try {
            if (Test-ServiceMode) {
                sc.exe stop DostupVPN 2>$null | Out-Null
            } elseif ([Environment]::OSVersion.Version.Major -lt 10) {
                Stop-Process -Name mihomo -Force -ErrorAction SilentlyContinue
            } else {
                Start-Process cmd.exe -ArgumentList "/c taskkill /F /IM mihomo.exe & powershell -ExecutionPolicy Bypass -NoProfile -File `"$DOSTUP_DIR\dns-helper.ps1`" restore" -Verb RunAs -Wait -WindowStyle Hidden
            }
            $osVer = [Environment]::OSVersion.Version
            if ($osVer.Major -lt 10) {
                $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                Set-ItemProperty -Path $reg -Name ProxyEnable -Value 0
            }
        } catch { }
    }
    $tray.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

try {
    [System.Windows.Forms.Application]::Run()
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
'@
$trayPs1 | Set-Content -Path "$DOSTUP_DIR\DostupVPN-Tray.ps1" -Encoding UTF8
Write-OK 'Tray application created'

# DNS helper script (Win 10+ only — TUN mode)
if ([Environment]::OSVersion.Version.Major -ge 10) {
    Write-Step 'Creating DNS helper...'
    $dnsHelper = @'
# DNS Helper for Dostup VPN (Win 10+)
# Usage: powershell -ExecutionPolicy Bypass -NoProfile -File dns-helper.ps1 <set|restore|check-recovery>

$DOSTUP_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$DNS_SAVE_FILE = "$DOSTUP_DIR\original_dns.json"

function Get-ActiveAdapter {
    # Find active non-virtual, non-TUN adapter
    $adapters = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and
        $_.InterfaceDescription -notmatch 'Hyper-V|Loopback|TAP-Windows|Wintun|WireGuard|VPN'
    }
    if ($adapters -is [array]) {
        # Prefer physical adapters (Wi-Fi or Ethernet)
        $preferred = $adapters | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless|Ethernet|Realtek|Intel|Broadcom|Qualcomm|Killer|Marvell' }
        if ($preferred) {
            if ($preferred -is [array]) { return $preferred[0] } else { return $preferred }
        }
        return $adapters[0]
    }
    return $adapters
}

function Set-DostupDns {
    $adapter = Get-ActiveAdapter
    if (-not $adapter) {
        Write-Host '[DNS] No active network adapter found' -ForegroundColor Yellow
        return
    }
    $alias = $adapter.InterfaceAlias

    # Save original DNS
    $currentDns = Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $originalAddresses = @()
    if ($currentDns -and $currentDns.ServerAddresses) {
        # Don't save if already set to our DNS
        $current = ($currentDns.ServerAddresses | Sort-Object) -join ','
        if ($current -eq '8.8.8.8,9.9.9.9' -or $current -eq '9.9.9.9,8.8.8.8') {
            Write-Host "[DNS] Already set to 8.8.8.8/9.9.9.9 on $alias" -ForegroundColor Green
            return
        }
        $originalAddresses = @($currentDns.ServerAddresses)
    }

    $saveData = @{
        InterfaceAlias = $alias
        OriginalDns = $originalAddresses
    }
    $json = $saveData | ConvertTo-Json
    [System.IO.File]::WriteAllText($DNS_SAVE_FILE, $json, (New-Object System.Text.UTF8Encoding($false)))

    # Set public DNS
    Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses @('8.8.8.8','9.9.9.9')
    & ipconfig /flushdns 2>$null | Out-Null
    Write-Host "[DNS] Set 8.8.8.8/9.9.9.9 on $alias" -ForegroundColor Green
}

function Restore-DostupDns {
    if (-not (Test-Path $DNS_SAVE_FILE)) {
        return
    }
    try {
        $saved = Get-Content $DNS_SAVE_FILE -Raw | ConvertFrom-Json
        $alias = $saved.InterfaceAlias

        # Check adapter still exists
        $adapter = Get-NetAdapter -Name $alias -ErrorAction SilentlyContinue
        if (-not $adapter) {
            Remove-Item $DNS_SAVE_FILE -Force -ErrorAction SilentlyContinue
            return
        }

        if ($saved.OriginalDns -and $saved.OriginalDns.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $saved.OriginalDns
            Write-Host "[DNS] Restored to $($saved.OriginalDns -join ', ') on $alias" -ForegroundColor Green
        } else {
            # Original was DHCP
            Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses
            Write-Host "[DNS] Restored to DHCP on $alias" -ForegroundColor Green
        }
        & ipconfig /flushdns 2>$null | Out-Null
        Remove-Item $DNS_SAVE_FILE -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[DNS] Restore failed: $_" -ForegroundColor Yellow
        Remove-Item $DNS_SAVE_FILE -Force -ErrorAction SilentlyContinue
    }
}

function Test-DnsRecovery {
    if ((Test-Path $DNS_SAVE_FILE) -and -not (Get-Process -Name 'mihomo' -ErrorAction SilentlyContinue)) {
        Write-Host '[DNS] Crash recovery: restoring DNS...' -ForegroundColor Yellow
        Restore-DostupDns
    }
}

# Main
if ($args.Count -gt 0) {
    switch ($args[0]) {
        'set' { Set-DostupDns }
        'restore' { Restore-DostupDns }
        'check-recovery' { Test-DnsRecovery }
    }
}
'@
    $dnsHelper | Set-Content -Path "$DOSTUP_DIR\dns-helper.ps1" -Encoding UTF8
    Write-OK 'DNS helper created'
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

Write-OK 'Desktop shortcut created'

Write-Step 'Creating tray launcher...'
# VBScript launcher to start tray without visible console window
$vbsContent = "CreateObject(""Wscript.Shell"").Run ""powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """"$DOSTUP_DIR\DostupVPN-Tray.ps1"""""", 0, False"
[System.IO.File]::WriteAllText("$DOSTUP_DIR\LaunchTray.vbs", $vbsContent, (New-Object System.Text.UTF8Encoding($false)))
Write-OK 'Tray launcher created'

Write-Step 'Creating startup shortcut for tray...'
$startupFolder = [Environment]::GetFolderPath('Startup')
$trayLnk = $WshShell.CreateShortcut("$startupFolder\DostupVPN-Tray.lnk")
$trayLnk.TargetPath = "wscript.exe"
$trayLnk.Arguments = "`"$DOSTUP_DIR\LaunchTray.vbs`""
$trayLnk.WorkingDirectory = $DOSTUP_DIR
if (Test-Path $iconPath) {
    $trayLnk.IconLocation = "$iconPath,0"
}
$trayLnk.Save()
Write-OK 'Startup shortcut created'

# Compile C# service wrapper (Win 10+ only)
$serviceCreated = $false
$osVersion = [Environment]::OSVersion.Version
$svcExe = "$DOSTUP_DIR\DostupVPN-Service.exe"

if ($osVersion.Major -ge 10) {
    Write-Step 'Compiling service wrapper...'
    $csPath = "$DOSTUP_DIR\DostupVPN-Service.cs"
    $csSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.ServiceProcess;

public class DostupVPNService : ServiceBase
{
    private Process _mihomo;
    private volatile bool _stopping;
    private StreamWriter _logStream;

    public DostupVPNService() { ServiceName = "DostupVPN"; CanStop = true; }

    protected override void OnStart(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        string exe = Path.Combine(dir, "mihomo.exe");
        string log = Path.Combine(dir, "logs", "mihomo.log");
        Directory.CreateDirectory(Path.Combine(dir, "logs"));

        _stopping = false;
        _logStream = new StreamWriter(log, false) { AutoFlush = true };

        _mihomo = new Process();
        _mihomo.StartInfo.FileName = exe;
        _mihomo.StartInfo.Arguments = "-d \"" + dir + "\"";
        _mihomo.StartInfo.UseShellExecute = false;
        _mihomo.StartInfo.RedirectStandardOutput = true;
        _mihomo.StartInfo.RedirectStandardError = true;
        _mihomo.StartInfo.CreateNoWindow = true;
        _mihomo.EnableRaisingEvents = true;
        _mihomo.OutputDataReceived += (s, e) => { if (e.Data != null) try { _logStream.WriteLine(e.Data); } catch {} };
        _mihomo.ErrorDataReceived += (s, e) => { if (e.Data != null) try { _logStream.WriteLine(e.Data); } catch {} };
        _mihomo.Exited += (s, e) => {
            if (!_stopping) { this.Stop(); }
        };

        _mihomo.Start();
        _mihomo.BeginOutputReadLine();
        _mihomo.BeginErrorReadLine();

        // Set DNS to 8.8.8.8/9.9.9.9 (runs as SYSTEM — no UAC)
        try {
            string dnsHelper = Path.Combine(dir, "dns-helper.ps1");
            if (File.Exists(dnsHelper)) {
                var dns = new Process();
                dns.StartInfo.FileName = "powershell.exe";
                dns.StartInfo.Arguments = "-ExecutionPolicy Bypass -NoProfile -File \"" + dnsHelper + "\" set";
                dns.StartInfo.UseShellExecute = false;
                dns.StartInfo.CreateNoWindow = true;
                dns.Start();
                dns.WaitForExit(10000);
            }
        } catch {}
    }

    protected override void OnStop()
    {
        // Restore DNS before stopping mihomo
        try {
            string dir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            string dnsHelper = Path.Combine(dir, "dns-helper.ps1");
            if (File.Exists(dnsHelper)) {
                var dns = new Process();
                dns.StartInfo.FileName = "powershell.exe";
                dns.StartInfo.Arguments = "-ExecutionPolicy Bypass -NoProfile -File \"" + dnsHelper + "\" restore";
                dns.StartInfo.UseShellExecute = false;
                dns.StartInfo.CreateNoWindow = true;
                dns.Start();
                dns.WaitForExit(10000);
            }
        } catch {}

        _stopping = true;
        if (_mihomo != null && !_mihomo.HasExited)
        {
            _mihomo.Kill();
            _mihomo.WaitForExit(5000);
        }
        try { _logStream.Close(); } catch {}
    }

    public static void Main() { ServiceBase.Run(new DostupVPNService()); }
}
'@
    [System.IO.File]::WriteAllText($csPath, $csSource, (New-Object System.Text.UTF8Encoding($false)))

    $cscDir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
    $cscExe = Join-Path $cscDir 'csc.exe'
    if (Test-Path $cscExe) {
        $cscOutput = & $cscExe /nologo /target:exe /out:$svcExe /r:System.ServiceProcess.dll $csPath 2>&1
        if (Test-Path $svcExe) {
            Write-OK 'Service wrapper compiled'
        } else {
            Write-Fail "Service compilation failed: $cscOutput"
            Write-Info 'Using fallback mode (UAC on each toggle)'
        }
    } else {
        Write-Info 'csc.exe not found, using fallback mode'
    }
    Remove-Item $csPath -Force -ErrorAction SilentlyContinue
}

Write-Step 'Configuring firewall and service...'
try {
    $elevatedCommands = @(
        "netsh advfirewall firewall delete rule name=all program=`"$MIHOMO_BIN`"",
        "netsh advfirewall firewall add rule name=`"Mihomo Proxy (Inbound)`" dir=in action=allow program=`"$MIHOMO_BIN`" enable=yes profile=any",
        "netsh advfirewall firewall add rule name=`"Mihomo Proxy (Outbound)`" dir=out action=allow program=`"$MIHOMO_BIN`" enable=yes profile=any"
    )

    if ($osVersion.Major -ge 10 -and (Test-Path $svcExe)) {
        $sddl = 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;LCRPWPCRRC;;;IU)'
        $elevatedCommands += @(
            "sc.exe delete DostupVPN",
            "sc.exe create DostupVPN binPath= `"$svcExe`" start= demand type= own",
            "sc.exe sdset DostupVPN $sddl",
            "sc.exe failure DostupVPN reset= 86400 actions= restart/5000/restart/30000//"
        )
    }

    $allCommands = $elevatedCommands -join ' & '
    Start-Process -FilePath 'cmd' -ArgumentList "/c $allCommands" -Verb RunAs -Wait -WindowStyle Hidden

    # Check if service was created
    if ($osVersion.Major -ge 10) {
        sc.exe query DostupVPN 2>$null | Out-Null
        $serviceCreated = ($LASTEXITCODE -eq 0)
    }

    if ($serviceCreated) {
        Write-OK 'Firewall and service configured (no UAC on toggle)'
    } else {
        Write-OK 'Firewall configured'
    }
} catch {
    Write-Info 'Firewall: manual configuration may be needed'
}

Write-Step 'Starting Mihomo...'
Write-Host ''
if ($serviceCreated) {
    sc.exe start DostupVPN 2>$null | Out-Null
} elseif ($osVersion.Major -lt 10) {
    Start-Process cmd.exe -ArgumentList "/c `"`"$MIHOMO_BIN`" -d `"$DOSTUP_DIR`" > `"$LOGS_DIR\mihomo.log`" 2>&1`"" -WindowStyle Hidden
} else {
    Start-Process cmd.exe -ArgumentList "/c `"`"$MIHOMO_BIN`" -d `"$DOSTUP_DIR`" > `"$LOGS_DIR\mihomo.log`" 2>&1`"" -Verb RunAs -WindowStyle Hidden
}
if (Wait-MihomoStart 5) {
    # Enable system proxy for Windows < 10
    if ($osVersion.Major -lt 10) {
        $proxyPort = Get-MixedPort
        $proxyServer = "127.0.0.1:$proxyPort"
        $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
        Set-ItemProperty -Path $regPath -Name ProxyServer -Value $proxyServer
        Write-OK "System proxy enabled: $proxyServer"
    }

    # Launch tray application
    $trayVbs = "$DOSTUP_DIR\LaunchTray.vbs"
    if (Test-Path $trayVbs) {
        Start-Process wscript.exe -ArgumentList "`"$trayVbs`"" -WindowStyle Hidden
        Write-OK 'Tray application started'
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
    Write-Host 'System tray:'
    Write-Host '  - VPN icon in the notification area (auto-start with Windows)'
    Write-Host ''
} else {
    Write-Host '[FAIL] Failed to start Mihomo' -ForegroundColor Red
    Write-Host "Check logs: $LOGS_DIR"
}

Write-Host ''
Write-Host 'Window will close in 5 seconds...'
Start-Sleep -Seconds 5
