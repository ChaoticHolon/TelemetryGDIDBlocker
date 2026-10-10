<#
.SYNOPSIS
    Telemetry & GDID Blocker (TelemetryGDIDBlocker.ps1) - tiered lockdown of Windows GDID
    reporting and Microsoft telemetry.

.DESCRIPTION
    Protection tiers (run -Action Options for exactly what each changes and breaks):

      Standard  Telemetry off with as little visible breakage as possible.
      Gaming    Maximum blocking for people who just want games to work: minus
                anything that breaks the Microsoft Store, Xbox / Xbox Live / Game Pass
                (telemetry service, Xbox services and OneSettings forced on, Store and
                update plumbing untouched).
      Maximum   Standard + personal Microsoft accounts blocked (no GDID), GDID device-graph
                registration (CDP/DDS/Project Rome), remote configuration (OneSettings/ECS),
                Defender cloud, DO cloud, settings sync; SmartScreen off with no opt-out.
      Stripped  Maximum + Windows Update and definition updates off. Only for builds
                that already ship without Defender and Windows Update (e.g. GhostSpectre,
                updated by manual in-place upgrade).

    Keep switches - leave these working:
      -KeepGaming     Store, Xbox, Game Pass (automatic in the Gaming tier)
      -KeepOffice     Office cloud: Designer, Editor, online templates, Teams remote config
      -KeepDevTools   Visual Studio, VS Code, Azure Application Insights / App Center hosts
      -KeepPhoneLink  Phone Link / Nearby Sharing / cross-device clipboard (Gaming, Maximum,
                      Stripped; Standard leaves them on). This IS the GDID device graph,
                      so keeping it leaves GDID registration unblocked.
      -KeepVoice      Voice typing, voice access and online speech recognition
      -KeepLocation   Location service and automatic time zone (off at every tier)

    SmartScreen (URL / download reputation lookups): off at every tier.
      -KeepSmartScreen keeps it on at Standard and Gaming; Maximum and Stripped have no
      opt-out.
    Defender cloud protection (MAPS): off at Gaming, Maximum and Stripped, no opt-out.
      Left on at Standard. Local scanning and definition updates are not affected.

    Personal Microsoft account sign-in is BLOCKED by default at Maximum and Stripped: the
      wlidsvc service (Windows' Microsoft account sign-in service, which also creates the
      GDID) is firewalled,
      the "Block Microsoft accounts" policy is set, and login.live.com / account.live.com
      are sinkholed. This is the only thing that stops a GDID being created.
      Work/school (Entra ID) accounts are NOT affected: Office, Teams, Visual Studio and
      Azure sign-in with a work account keep working.
      -KeepAccounts   Leave personal Microsoft accounts working (GDID is then created).
      -KeepDevTools   Leaves login.live.com and account.live.com reachable so Visual Studio /
                      VS Code / GitHub can
                      sign in with a personal account through the web browser; wlidsvc stays
                      blocked, so no GDID. (VS: Tools > Options > Environment > Accounts >
                      "System web browser".)
      Apply refuses to run over a Microsoft-account Windows sign-in (switch to a local
      account first), and detects Office signed in with a personal account, OneDrive,
      Visual Studio / VS Code and the Store, and tells you which to keep.

    Disabled by default at every tier (Keep switch to opt out):
      Windows Hello PIN / biometrics  -KeepHello     You MUST know the account's password,
                                                     or you can lock yourself out.
      OneDrive sync client            -KeepOneDrive  Files stay on disk.
      Edge sign-in / sync             -KeepEdgeSync  Also startup boost, background mode.
    Removed by default at every tier:
      Microsoft Edge                  -KeepEdge      Uninstalled with its own installer,
                                                     WebView2 never touched, reinstall blocked
                                                     and re-removed at startup if it returns.
                                                     Not undone by Roll back. Closed first
                                                     only if you allow stopping programs.
      WebView2 is left intact at every tier.
    Cortana: off by policy and its app removed for all users at every tier (Roll back does not
      reinstall it; it is in the Microsoft Store).

    Opt-in, any tier:
      -DisableSearch  Windows Search off: indexer service (WSearch) disabled, Start/taskbar
                      search box blocked and hidden. Start menu still opens; typing in it no
                      longer searches. Offers to install Everything (file search) and
                      Open-Shell (Start menu with program search) via winget.
      -BlockGpuTelemetry  NVIDIA, AMD and Intel telemetry off: NVIDIA telemetry service,
                      opt-out flags and telemetry hosts (driver updates and sign-in hosts
                      left alone); AMD User Experience Program and Intel Computing
                      Improvement Program blocked. Anything not installed is skipped.

    Always on, no opt-out: Windows Spotlight / lock-screen and Start "suggestions" blocked.
    Never touched: local crash dumps (only uploading of error reports is blocked),
    activation, time sync, winget (only its own telemetry is turned off).
    Windows Insider builds are not supported; the script applies as normal on them.

    Windows edition is detected and used:
      Enterprise / Education / LTSC / IoT / Server  AllowTelemetry = 0 (Security), which
                                                    these editions honour.
      Home / Pro                                    AllowTelemetry = 1 (Required); 0 is
                                                    not honoured. Per-user settings are
                                                    applied for the Enterprise-only policies.
      Gaming / -KeepGaming on any edition           AllowTelemetry = 1.
    MDM-enrolled PCs keep dmwappushservice.

    Other actions:
      Status      What is applied, drift, edition, and the current GDID.
      Options     Explains every tier, switch and opt-in option, and compares the tiers.
      TempUnlock  (any tier) Temporarily turns telemetry fully on (AllowTelemetry 3; DiagTrack,
                  OneSettings, error reporting and all event hosts unblocked; OneSettings
                  cache refreshed) for games that refuse to start or sync saves without it,
                  e.g. Forza Horizon 6 E:0-17. Stays until Relock or the next reboot.
      Relock      Ends Temp Unlock now.
      RemoveEdge  Uninstalls Microsoft Edge without applying a tier (WebView2 is kept).
      Wipe        Wipes local GDID state. Unless personal Microsoft accounts are blocked,
                  Windows creates a NEW GDID the next time a personal account signs in:
                  this only breaks continuity with the old ID.
      Rollback    Restores the system from backups to its original state (does not
                  reinstall apps): every changed setting goes back to its recorded
                  original, and the hosts block, firewall rules and scheduled tasks are
                  removed. Logs are kept.

    All changes are made by a SYSTEM scheduled task so protected services and tasks
    can be changed. SYSTEM tasks re-apply the chosen tier at startup and at each sign-in,
    so feature updates and Defender reverts are corrected automatically.

    login.live.com and account.live.com are blocked only while personal Microsoft accounts
    are (Maximum and Stripped, without -KeepAccounts).

    Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
    Double-click Start.cmd (one folder up) to open the menu. From a terminal:
    powershell -ExecutionPolicy Bypass -File .\TelemetryGDIDBlocker.ps1
    powershell -ExecutionPolicy Bypass -File .\TelemetryGDIDBlocker.ps1 -Action Apply -Tier Gaming -KeepOffice
    powershell -ExecutionPolicy Bypass -File .\TelemetryGDIDBlocker.ps1 -Action Apply -Tier Maximum -KeepDevTools -KeepLocation
    powershell -ExecutionPolicy Bypass -File .\TelemetryGDIDBlocker.ps1 -Action TempUnlock
    powershell -ExecutionPolicy Bypass -File .\TelemetryGDIDBlocker.ps1 -Action Status

.NOTES
    Stopping things: the script asks once, when it starts, whether it may stop services
    and close programs (Edge, OneDrive). Yes = it does so whenever needed, with no further
    prompts. No = nothing is stopped, and it offers to restart Windows to finish.
    Always = yes, and the question is not asked again (Options > A turns it off). -StopNow
    approves in advance; -Force without -StopNow never stops anything. The startup and
    sign-in tasks never stop anything.

    Copyright (C) 2026 ChaoticHolon & contributors.
    This program is free software: you can redistribute it and/or modify it under the
    terms of the GNU General Public License as published by the Free Software Foundation,
    either version 3 of the License, or (at your option) any later version. It is
    distributed WITHOUT ANY WARRANTY; see the LICENSE file for details.
    SPDX-License-Identifier: GPL-3.0-or-later
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Apply', 'Status', 'Options', 'TempUnlock', 'Relock', 'RemoveEdge', 'Wipe', 'Rollback')]
    [string]$Action = 'Menu',
    [ValidateSet('Standard', 'Gaming', 'Maximum', 'Stripped')]
    [string]$Tier,
    [switch]$KeepGaming,
    [switch]$KeepOffice,
    [switch]$KeepDevTools,
    [switch]$KeepPhoneLink,
    [switch]$KeepVoice,
    [switch]$KeepHello,
    [switch]$KeepOneDrive,
    [switch]$KeepEdgeSync,
    [switch]$KeepEdge,
    [switch]$KeepSmartScreen,
    [switch]$KeepLocation,
    [switch]$KeepAccounts,
    [switch]$Force,
    [switch]$StopNow,
    [switch]$DisableSearch,
    [switch]$BlockGpuTelemetry,
    [ValidateSet('Enforce', 'EnforceBoot', 'Rollback', 'WipeSystem', 'RemoveEdge')]
    [string]$Internal,
    [string]$RunLabel
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$ScriptName      = 'Telemetry & GDID Blocker'
$ScriptVersion   = '1.0'
$InstallDir      = Join-Path $env:ProgramData 'TelemetryGDIDBlocker'
$InstalledScript = Join-Path $InstallDir 'TelemetryGDIDBlocker.ps1'
$InstalledLib    = Join-Path $InstallDir 'Lib'
$ConfigPath      = Join-Path $InstallDir 'config.json'
$StatePath       = Join-Path $InstallDir 'state.json'
$LogPath         = Join-Path $InstallDir 'last-run.log'
$LogDir          = Join-Path $InstallDir 'Logs'                     # one log per run, kept after Roll back
$WipePath        = Join-Path $InstallDir 'wipe.json'
$StopFlag        = Join-Path $InstallDir 'allow-stop.flag'   # present only during a run the user approved
$HostsBackup     = Join-Path $InstallDir 'hosts.original'
$PrefsPath       = Join-Path $InstallDir 'prefs.json'                # saved answers (kept by Roll back)
$TaskFolder      = '\TelemetryGDIDBlocker\'
$BootTask        = 'Enforce at startup'
$LogonTask       = 'Enforce at sign-in'
$RunTask         = 'Run once'
$FwGroup         = 'TelemetryGDIDBlocker'
$HostsPath       = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$MarkBegin       = '# BEGIN TelemetryGDIDBlocker (managed by TelemetryGDIDBlocker.ps1 - edits inside are overwritten)'
$MarkEnd         = '# END TelemetryGDIDBlocker'

# ---------------------------------------------------------------------------
# Components (Scripts\Lib). Loaded in this order: later files use what earlier ones define.
# ---------------------------------------------------------------------------
$MainScript = $PSCommandPath
$LibDir     = Join-Path $PSScriptRoot 'Lib'
foreach ($lib in 'Tiers', 'HostsData', 'Catalog', 'Environment', 'Console', 'Config', 'Items', 'FirewallHosts', 'Enforce', 'SystemTasks', 'Runner', 'Views', 'Actions', 'Menu') {
    $libPath = Join-Path $LibDir "$lib.ps1"
    if (-not (Test-Path -LiteralPath $libPath)) { throw "Missing $libPath. Keep the Lib folder next to TelemetryGDIDBlocker.ps1." }
    . $libPath
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if ($Internal) {
    # Running as SYSTEM from a scheduled task.
    try {
        if ((Test-Path -LiteralPath $LogPath) -and (Get-Item -LiteralPath $LogPath).Length -gt 262144) { Remove-Item -LiteralPath $LogPath -Force }
        Write-RunLog ("--- {0} {1} ---" -f $(if ($RunLabel) { $RunLabel } elseif ($Internal -eq 'EnforceBoot') { 'Startup' } elseif ($Internal -eq 'Enforce') { 'Sign-in' } else { $Internal }), (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        # The approval flag is only honoured if fresh, so a leftover can never reach a startup/sign-in run.
        $script:AllowStop = ($Internal -ne 'EnforceBoot') -and (Test-Path -LiteralPath $StopFlag) -and ((Get-Item -LiteralPath $StopFlag).LastWriteTime -gt (Get-Date).AddMinutes(-20))
        if ($Internal -eq 'EnforceBoot') { Remove-Item -LiteralPath $StopFlag -Force -ErrorAction SilentlyContinue }
        switch ($Internal) {
            'Enforce' {
                $cfg = Get-Config
                if ($cfg) { Invoke-Enforce $cfg } else { Write-RunLog 'No configuration; nothing to enforce.' }
            }
            'EnforceBoot' {
                $pend = Read-JsonFile $WipePath
                if ($pend -and $pend.PSObject.Properties['Pending'] -and $pend.Pending) { Invoke-WipeSystem }
                $cfg = Get-Config
                if ($cfg) {
                    if ($cfg.Unlocked) { $cfg.Unlocked = $false; Save-Config $cfg; Write-RunLog 'Temp Unlock ended by reboot.' }
                    Invoke-Enforce $cfg
                }
                else { Write-RunLog 'No configuration; nothing to enforce.' }
            }
            'Rollback' { Invoke-Enforce $null }
            'WipeSystem'   { Invoke-WipeSystem }
            'RemoveEdge' { Invoke-RemoveEdgeSystem }
        }
    }
    catch { Write-RunLog "ERROR: $($_.Exception.Message)" }
    finally {
        Write-RunLog '== DONE =='
        if ($Internal -eq 'EnforceBoot') { [void](Save-RunLog 'Startup') }
    }
    return
}

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    throw 'Run this from 64-bit PowerShell (not the x86 version).'
}

# Prefer PowerShell 7 when it is installed, and elevate if needed. Already-elevated runs
# switch to pwsh in the same window; otherwise a new elevated window opens.
$pwsh = $null
if ($PSVersionTable.PSVersion.Major -lt 7) { $pwsh = Find-Pwsh }
$isAdmin = Test-Admin
$needAdmin = ($Action -ne 'Options')
if ($pwsh -or ($needAdmin -and -not $isAdmin)) {
    $exe = if ($pwsh) { $pwsh } else { (Get-Process -Id $PID).Path }
    $pass = @()
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v.IsPresent) { $pass += "-$k" } }
        else { $pass += "-$k"; $pass += [string]$v }
    }
    if ($isAdmin -or -not $needAdmin) {
        & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @pass
        return
    }
    $argList = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($a in $pass) { if ($a -like '-*') { $argList += $a } else { $argList += "`"$a`"" } }
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList $argList
    return
}

if ($Action -in 'Menu', 'Options') { Set-ConsoleSize; Disable-QuickEdit }
if ($Action -eq 'Menu') { try { Clear-Host } catch { } }
Show-Banner
if ($Action -eq 'Options') { Show-Options; return }

$cliKeeps = @()
if ($KeepGaming)    { $cliKeeps += 'Gaming' }
if ($KeepOffice)    { $cliKeeps += 'Office' }
if ($KeepDevTools)  { $cliKeeps += 'DevTools' }
if ($KeepPhoneLink) { $cliKeeps += 'PhoneLink' }
if ($KeepVoice)     { $cliKeeps += 'Voice' }
if ($KeepHello)     { $cliKeeps += 'Hello' }
if ($KeepOneDrive)  { $cliKeeps += 'OneDrive' }
if ($KeepEdgeSync)  { $cliKeeps += 'EdgeSync' }
if ($KeepEdge)      { $cliKeeps += 'Edge' }
if ($KeepSmartScreen) { $cliKeeps += 'SmartScreen' }
if ($KeepLocation)  { $cliKeeps += 'Location' }
if ($KeepAccounts)  { $cliKeeps += 'Accounts' }

$script:HelloAck = $false
if ($Action -in 'Menu', 'Apply') { Show-HelloNotice }

$script:StopApproved = $false
if ($Action -in 'Menu', 'Apply', 'RemoveEdge', 'Rollback', 'Wipe', 'TempUnlock', 'Relock') {
    $script:StopApproved = Request-StopApproval
}

switch ($Action) {
    'Menu'       { Show-Menu }
    'Apply'      {
        $applyTier = $Tier; $applyKeeps = $cliKeeps
        $applyNs = [bool]$DisableSearch; $applyGt = [bool]$BlockGpuTelemetry
        if (-not $applyTier) {
            # No -Tier: re-apply the saved tier and choices; switches given now are added.
            $saved = Get-Config
            if (-not $saved) { throw 'No tier is applied yet. Specify -Tier Standard, Gaming, Maximum or Stripped.' }
            $applyTier = $saved.Tier
            $applyKeeps = @((Get-SavedKeeps $applyTier).Kept + $cliKeeps | Select-Object -Unique)
            $applyNs = $applyNs -or $saved.NoSearch
            $applyGt = $applyGt -or $saved.GpuTel
            Write-Host ("  Re-applying the saved tier: {0}" -f $applyTier) -ForegroundColor Cyan
        }
        Invoke-Apply $applyTier @{ Keeps = $applyKeeps; NoSearch = $applyNs; GpuTel = $applyGt }
    }
    'RemoveEdge' { Invoke-RemoveEdge }
    'Status'     { Show-Status }
    'Rollback'   { Invoke-Rollback }
    'Wipe'       { Invoke-Wipe }
    'TempUnlock' { Invoke-TempUnlock $true }
    'Relock'     { Invoke-TempUnlock $false }
}
Restore-QuickEdit
