<#
.SYNOPSIS
    Installs and/or repairs the core Xbox / Game Pass PC app stack on Windows Server 2025.

.AUTHOR
    DJ Stomp <85457381+DJStompZone@users.noreply.github.com>

.LICENSE
    MIT

.GITHUB
    https://github.com/seamoolab/winserver25gaming

.PARAMETER IncludeLegacyConsoleCompanion
    Also installs/registers the legacy Xbox Console Companion app.

.EXAMPLE
    .\Install-XboxGamingStack.ps1

.EXAMPLE
    .\Install-XboxGamingStack.ps1 -IncludeLegacyConsoleCompanion
#>

[CmdletBinding()]
param(
    [switch]$IncludeLegacyConsoleCompanion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,
        [Parameter(Mandatory)]
        [string]$Message
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    switch ($Level) {
        'INFO'  { Write-Host "[$ts] [INFO ] $Message" }
        'WARN'  { Write-Host "[$ts] [WARN ] $Message" }
        'ERROR' { Write-Host "[$ts] [ERROR] $Message" }
    }
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-AppxByName {
    param([Parameter(Mandatory)][string]$Name)
    # AppX is per-user, but these apps usually get installed for the current user. We still check AllUsers to help repair cases.
    $pkgs = @(Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue)
    if ($pkgs.Count -eq 0) {
        $pkgs = @(Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue)
    }
    return $pkgs
}

function Register-AppxPackage {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $pkgs = @(Get-AppxByName -Name $Name)
    if ($pkgs.Count -eq 0) {
        Write-Log -Level 'WARN' -Message "Package '$Name' not found to register."
        return
    }

    foreach ($pkg in $pkgs) {
        $manifestPath = Join-Path -Path $pkg.InstallLocation -ChildPath 'AppXManifest.xml'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            Write-Log -Level 'WARN' -Message "Manifest missing for '$Name' at '$manifestPath' (InstallLocation='$($pkg.InstallLocation)')."
            continue
        }

        Write-Log -Level 'INFO' -Message "Re-registering '$Name' from '$manifestPath'..."
        Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop | Out-Null
    }
}

function Install-MsStoreAppViaWinget {
    param(
        [Parameter(Mandatory)]
        [string]$WingetId,
        [Parameter(Mandatory)]
        [string]$Label
    )

    if (-not (Test-CommandExists -Name 'winget')) {
        throw "winget is not available. Install 'App Installer' (winget) first, or install these apps via Store manually."
    }

    Write-Log -Level 'INFO' -Message "Installing '$Label' via winget (msstore) id='$WingetId'..."
    & winget install --id $WingetId --source msstore --accept-package-agreements --accept-source-agreements --silent | Out-Host
}

function Ensure-Appx {
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,
        [Parameter(Mandatory)]
        [string]$Label,
        [Parameter()]
        [string]$WingetId
    )

    $pkgs = @(Get-AppxByName -Name $PackageName)
    if ($pkgs.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($WingetId)) {
            Write-Log -Level 'WARN' -Message "Missing '$Label' ($PackageName) and no winget id provided. Skipping install attempt."
        } else {
            Install-MsStoreAppViaWinget -WingetId $WingetId -Label $Label
        }
    } else {
        Write-Log -Level 'INFO' -Message "Found '$Label' ($PackageName)."
    }

    Register-AppxPackage -Name $PackageName
}

function Ensure-ServiceRunning {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log -Level 'WARN' -Message "Service '$Name' not found."
        return
    }

    if ($svc.StartType -ne 'Automatic') {
        Write-Log -Level 'INFO' -Message "Setting service '$Name' start type to Automatic..."
        Set-Service -Name $Name -StartupType Automatic
    }

    if ($svc.Status -ne 'Running') {
        Write-Log -Level 'INFO' -Message "Starting service '$Name'..."
        Start-Service -Name $Name
    } else {
        Write-Log -Level 'INFO' -Message "Service '$Name' is already running."
    }
}

function Ensure-VCRuntime {
    if (-not (Test-CommandExists -Name 'winget')) {
        Write-Log -Level 'WARN' -Message "winget not present; skipping VC++ runtime installs."
        return
    }

    $vcIds = @(
        @{ Id = 'Microsoft.VCRedist.2015+.x64'; Label = 'VC++ 2015-2022 x64' },
        @{ Id = 'Microsoft.VCRedist.2015+.x86'; Label = 'VC++ 2015-2022 x86' }
    )

    foreach ($vc in $vcIds) {
        Write-Log -Level 'INFO' -Message "Installing '$($vc.Label)' via winget id='$($vc.Id)'..."
        & winget install --id $vc.Id --accept-package-agreements --accept-source-agreements --silent | Out-Host
    }
}

function Ensure-WebView2 {
    if (-not (Test-CommandExists -Name 'winget')) {
        Write-Log -Level 'WARN' -Message "winget not present; skipping WebView2 Runtime install."
        return
    }

    Write-Log -Level 'INFO' -Message "Installing Microsoft Edge WebView2 Runtime via winget..."
    & winget install --id Microsoft.EdgeWebView2Runtime --accept-package-agreements --accept-source-agreements --silent | Out-Host
}

if (-not (Test-IsAdmin)) {
    throw "Run this script in an elevated PowerShell (Administrator)."
}

Write-Log -Level 'INFO' -Message "Starting Xbox / Game Pass PC component install+repair..."