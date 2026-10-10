# Telemetry & GDID Blocker - Environment.ps1
# Windows edition, build, MDM/Insider and modified-build detection; admin check.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

# ---------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------
function Get-WindowsEdition {
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $id = [string]$cv.EditionID
    $class = 'HomePro'
    if ($id -match '^(Enterprise|Education|IoTEnterprise|Server)') { $class = 'Enterprise' }
    $ltsc = ($id -match '^(Enterprise|IoTEnterprise)SN?$')
    $build = [int]$cv.CurrentBuildNumber
    $os = 'Windows 10'
    if ($build -ge 22000) { $os = 'Windows 11' }
    $pn = ([string]$cv.ProductName) -replace '^Windows 1[01] ', ''
    $lt = ''
    if ($ltsc) { $lt = ' [LTSC]' }
    $label = '{0} {1}{2} (EditionID {3}, build {4}.{5})' -f $os, $pn, $lt, $id, $build, $cv.UBR
    return @{ Id = $id; Class = $class; Ltsc = $ltsc; Build = $build; Label = $label }
}

function Test-MdmEnrolled {
    foreach ($k in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        if ($p -and $p.PSObject.Properties['UPN'] -and $p.UPN) { return $true }
    }
    return $false
}

function Test-InsiderEnrolled {
    $p = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\Applicability' -ErrorAction SilentlyContinue
    return [bool]($p -and $p.PSObject.Properties['BranchName'] -and $p.BranchName)
}

# Detects community-modified builds (GhostSpectre, Tiny11, Atlas, ReviOS, X-Lite, etc.).
# Builds rarely carry a reliable signature, so naming one is best-effort. What matters for
# this script is what the build removed, and that is checked directly whatever its name.
function Get-RemovedComponents {
    # Core Windows components missing from this install. This script never removes any of
    # these (Stripped only disables Windows Update), so a missing one means another tool did.
    $ed = Get-WindowsEdition
    $svc = [ordered]@{
        'Defender'          = 'WinDefend'
        'Windows Security'  = 'SecurityHealthService'
        'Security Center'   = 'wscsvc'
        'Windows Update'    = 'wuauserv'
        'Update Medic'      = 'WaaSMedicSvc'
        'servicing stack'   = 'TrustedInstaller'
    }
    $gone = @()
    foreach ($k in $svc.Keys) {
        if (-not (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc[$k])")) { $gone += $k }
    }
    # LTSC and Server ship without the Store, so its absence only counts elsewhere.
    if (-not $ed.Ltsc -and $ed.Id -notmatch '^Server' -and -not (Test-StoreInstalled)) { $gone += 'Microsoft Store' }
    return $gone
}

function Get-ModifiedBuild {
    # Returns @{ Name = builder name or ''; Removed = missing core components }.
    # Modified when either is set.
    $name = ''
    $marks = @(
        @{ P = 'HKLM:\SOFTWARE\WOW6432Node\GhostSpectre'; N = 'GhostSpectre' }
        @{ P = 'HKLM:\SOFTWARE\GhostSpectre';             N = 'GhostSpectre' }
        @{ P = (Join-Path $env:SystemDrive 'Ghost Toolbox'); N = 'GhostSpectre' }
        @{ P = (Join-Path $env:SystemRoot 'AtlasModules');   N = 'AtlasOS' }
    )
    foreach ($m in $marks) { if (Test-Path -LiteralPath $m.P) { $name = $m.N; break } }
    if (-not $name) {
        # Branding some builders write into the owner, OEM or product-name fields.
        $pat = 'ghost\s*spectre|tiny1[01]|atlas\s*os|revi\s*os|xlite|x-lite|superlite|nexus\s*lite|phoenix\s*lite|optimum\s*1[01]|kernel\s*os|ggos|\bxos\b|fox\s*os|ameliorated'
        $cv  = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $oem = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation' -ErrorAction SilentlyContinue
        foreach ($o in @($cv, $oem)) {
            if (-not $o) { continue }
            foreach ($n in @('ProductName', 'RegisteredOrganization', 'RegisteredOwner', 'Manufacturer', 'Model', 'SupportURL', 'SupportPhone')) {
                if ($o.PSObject.Properties[$n] -and [string]$o.$n -match $pat) { $name = "branded '$([string]$o.$n)'"; break }
            }
            if ($name) { break }
        }
    }
    return @{ Name = $name; Removed = @(Get-RemovedComponents) }
}

function Test-StoreInstalled {
    return [bool](Get-ChildItem -LiteralPath "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.WindowsStore_*' -Directory -ErrorAction SilentlyContinue)
}

function Get-LoadedUserSids {
    return @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } | ForEach-Object { $_.PSChildName })
}

function Test-HiveLoaded {
    param([string]$Path)
    if ($Path -match '^Registry::HKEY_USERS\\([^\\]+)\\') {
        return (Test-Path -LiteralPath "Registry::HKEY_USERS\$($Matches[1])")
    }
    return $true
}

function Get-TelemetryLevel {
    param([hashtable]$Config)
    if ($Config.Unlocked) { return 3 }
    if ($Config.Keeps -contains 'Gaming') { return 1 }
    if ((Get-WindowsEdition).Class -eq 'Enterprise') { return 0 }
    return 1
}


function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
