#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Nerdy Neighbor - Install Adobe Reader (no McAfee / no add-ons)
.DESCRIPTION
    Silently installs the latest 64-bit Adobe Acrobat Reader from Adobe's own
    enterprise/offline installer - the one with no McAfee, Norton or other
    bundled offers (those only come with the get.adobe.com web installer).
    Then it turns off Adobe's upsell nags and stops the Acrobat extension from
    being pushed into Chrome and Edge.
.NOTES
    Run:  irm reader.nerdyneighbor.net | iex        (elevated Windows PowerShell)
    Log:  C:\ProgramData\NerdyNeighbor\reader.log
    No options. If any Adobe Acrobat/Reader is already installed it changes
    nothing - paid Acrobat Pro looks the same to Windows, and we don't want to
    turn off features a customer paid for.
    To remove it: Settings > Apps > "Adobe Acrobat (64-bit)" > Uninstall.
#>

# Everything runs inside & { } so that under `irm | iex` nothing leaks into the
# tech's PowerShell window afterwards (ErrorActionPreference, functions,
# variables). `return` still works anywhere in here to stop early.
& {

$ErrorActionPreference = 'Stop'
# Add TLS 1.2 without switching off TLS 1.3 or anything else already enabled.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# When run via `irm ... | iex` the #Requires line is NOT enforced (that only
# works for a real .ps1 file), so check for elevation ourselves.
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  This needs an ELEVATED PowerShell (Run as Administrator)." -ForegroundColor Red
    Write-Host "  Close this window, reopen PowerShell as Administrator, and run again." -ForegroundColor Yellow
    Write-Host ""
    return
}

# --- Logging -----------------------------------------------------------------
$LogDir  = Join-Path $env:ProgramData 'NerdyNeighbor'
$LogFile = Join-Path $LogDir 'reader.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0}  [{1}]  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    switch ($Level) {
        'ERROR' { Write-Host "  $Message" -ForegroundColor Red }
        'WARN'  { Write-Host "  $Message" -ForegroundColor Yellow }
        'OK'    { Write-Host "  $Message" -ForegroundColor Green }
        default { Write-Host "  $Message" -ForegroundColor Gray }
    }
}

# --- Helpers -----------------------------------------------------------------
$UninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

# Any Acrobat/Reader: old 32-bit "Adobe Acrobat Reader DC", the current unified
# "Adobe Acrobat (64-bit)" (Reader and Pro share it), or "Adobe Acrobat DC ...".
function Get-AdobeReader {
    Get-ItemProperty -Path $UninstallRoots -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '^Adobe Acrobat' -and $_.Publisher -match 'Adobe' } |
        Select-Object -First 1
}

# Asks Adobe's own download service (the one get.adobe.com uses) for the latest Reader version.
function Get-LatestReaderVersion {
    $api = 'https://rdc.adobe.io/reader/products?lang=en&site=enterprise&os=Windows%2011&api_key=dc-get-adobereader-cdn'
    $r = Invoke-RestMethod -Uri $api -UseBasicParsing -TimeoutSec 30
    $v = @($r.products.reader)[0].version
    if ($v -notmatch '^\d+\.\d+\.\d+$') { throw "Adobe returned an unexpected version: '$v'" }
    $v
}

# Policy keys. The 64-bit unified app reads "Adobe Acrobat"; older 32-bit Reader
# reads "Acrobat Reader" (in the WOW6432Node view). Write all; unused ones are harmless.
$PolicyRoots = @(
    'HKLM:\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown',
    'HKLM:\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown',
    'HKLM:\SOFTWARE\WOW6432Node\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown'
)
# Acrobat's browser extensions, which the installer registers for every user.
$ExtensionKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Google\Chrome\Extensions\efaidnbmnnnibpcajpcglclefindmkaj',
    'HKLM:\SOFTWARE\Google\Chrome\Extensions\efaidnbmnnnibpcajpcglclefindmkaj',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions\elhekieabhbkpmcefcoobjddigjcaadp',
    'HKLM:\SOFTWARE\Microsoft\Edge\Extensions\elhekieabhbkpmcefcoobjddigjcaadp'
)

function Set-ReaderClean {
    foreach ($root in $PolicyRoots) {
        if (-not (Test-Path $root)) { New-Item -Path $root -Force | Out-Null }
        # No "upgrade to Acrobat Pro" / trial pop-ups.
        New-ItemProperty -Path $root -Name 'bAcroSuppressUpsell' -Value 1 -PropertyType DWord -Force | Out-Null
        # No AI Assistant pane / prompts.
        New-ItemProperty -Path $root -Name 'bEnableGentech' -Value 0 -PropertyType DWord -Force | Out-Null
    }
    Write-Log 'Turned off the "upgrade to Pro" and AI Assistant pop-ups.' 'OK'

    $removed = 0
    foreach ($k in $ExtensionKeys) {
        if (Test-Path $k) { Remove-Item -Path $k -Recurse -Force; $removed++ }
    }
    if ($removed) { Write-Log 'Stopped the Acrobat extension from being added to Chrome/Edge.' 'OK' }
    else          { Write-Log 'No Acrobat browser extension to block.' }
}

# --- Main --------------------------------------------------------------------
try {
    Write-Host ""
    Write-Host "  Nerdy Neighbor - Install Adobe Reader (no McAfee / no add-ons)" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "=== Run started on $env:COMPUTERNAME (user: $env:USERNAME) ==="

    $existing = Get-AdobeReader
    if ($existing) {
        Write-Log "Already installed: $($existing.DisplayName) $($existing.DisplayVersion)" 'OK'
        Write-Log 'Nothing to do - Adobe keeps it updated on its own. No settings were changed.'
        Write-Log 'Done.' 'OK'
        Write-Host ''
        return
    }

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'This PC runs 32-bit Windows. Current Adobe Reader is 64-bit only - get the 32-bit enterprise installer from get.adobe.com/reader/enterprise.'
    }

    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
    if ($drive.Free -lt 3GB) {
        throw ('Not enough free space on {0} ({1:N1} GB free, about 3 GB needed).' -f $env:SystemDrive, ($drive.Free / 1GB))
    }

    Write-Log 'Asking Adobe for the latest version...'
    $version = Get-LatestReaderVersion
    $code    = $version -replace '\.', ''          # 26.002.21931 -> 2600221931
    $file    = "AcroRdrDCx64${code}_en_US.exe"
    $url     = "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/$code/$file"
    Write-Log "Latest is $version (offline installer, no bundled offers)."

    $work = Join-Path $LogDir 'reader-setup'
    if (Test-Path $work) { Remove-Item -Path $work -Recurse -Force }
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $exe = Join-Path $work $file

    try {
        Write-Log 'Downloading from Adobe (about 750 MB - this can take a few minutes)...'
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (Test-Path $curl) {
            & $curl -fL --retry 3 --progress-bar -o $exe $url
            if ($LASTEXITCODE -ne 0) { throw "Download failed (curl exit code $LASTEXITCODE)." }
        } else {
            $ProgressPreference = 'SilentlyContinue'   # the progress bar makes IWR 10x slower on PS 5.1
            Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
        }

        # Only run it if it's genuinely signed by Adobe.
        $sig = Get-AuthenticodeSignature -FilePath $exe
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Adobe Inc') {
            throw "The download is not validly signed by Adobe (signature: $($sig.Status)). Not running it."
        }
        Write-Log 'Download verified (signed by Adobe).' 'OK'

        Write-Log 'Installing silently (usually 2-5 minutes)...'
        $p = Start-Process -FilePath $exe -ArgumentList '/sAll /rs /msi EULA_ACCEPT=YES' -PassThru
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.WaitForExit(15000)) {
            Write-Host ('    still installing... {0:mm\:ss}' -f $sw.Elapsed) -ForegroundColor DarkGray
        }
        $rc = $p.ExitCode
        Write-Log "Installer finished (exit code $rc)."
    }
    finally {
        Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    $installed = Get-AdobeReader
    if (-not $installed -or $rc -notin 0, 3010, 1641) {
        throw "Adobe Reader did not install (installer exit code $rc)."
    }
    Write-Log "Installed: $($installed.DisplayName) $($installed.DisplayVersion)" 'OK'
    if ($rc -ne 0) { Write-Log 'A restart is needed to finish the install.' 'WARN' }

    Set-ReaderClean

    Write-Host ''
    Write-Log 'Done. Adobe Reader is installed with no McAfee or other add-ons.' 'OK'
    Write-Host ''
}
catch {
    Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
    Write-Host "  Log: $LogFile" -ForegroundColor Yellow
    Write-Host ""
}

}
