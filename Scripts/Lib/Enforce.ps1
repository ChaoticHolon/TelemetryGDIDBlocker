# Telemetry & GDID Blocker - Enforce.ps1
# The enforcement engine (runs as SYSTEM).
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

# ---------------------------------------------------------------------------
# Enforcement engine (runs as SYSTEM)
# ---------------------------------------------------------------------------
function Invoke-Enforce {
    param([hashtable]$Config)
    $script:PendingRestart = @()
    $state   = Get-State
    $desired = Get-DesiredItems $Config
    $wantIds = @{}
    foreach ($i in $desired) { $wantIds[$i.Id] = $true }

    if ($Config) {
        Write-RunLog ("Enforcing tier {0}  keeps=[{1}]  SmartScreen-off={2}  personal-accounts-blocked={3}  AllowTelemetry={4}  unlocked={5}" -f `
            $Config.Tier, ($Config.Keeps -join ','), (Test-SmartScreenOff $Config), (Test-AccountsBlocked $Config), (Get-TelemetryLevel $Config), $Config.Unlocked)
    }
    else { Write-RunLog 'Rolling back all changes' }

    # 1. Restore anything we changed that is no longer wanted
    foreach ($id in @($state.Keys)) {
        if ($wantIds.ContainsKey($id)) { continue }
        $e = $state[$id]
        if ($e.Item.Kind -eq 'Reg' -and -not (Test-HiveLoaded $e.Item.Path)) { continue }
        try {
            Restore-Item $e.Item $e.Orig
            Write-RunLog ("  restored {0}" -f (Get-ItemLabel $e.Item))
            $state.Remove($id)
        }
        catch { Write-RunLog ("  FAILED   restore {0} : {1}" -f (Get-ItemLabel $e.Item), $_.Exception.Message) }
    }

    # 2. Apply wanted items, recording originals the first time
    foreach ($i in $desired) {
        if ($i.Kind -notin 'Reg', 'Service', 'ServiceOn', 'Task') { continue }
        try {
            if (-not $state.ContainsKey($i.Id)) {
                $orig = Get-Original $i
                if ($orig.Missing) { continue }
                $state[$i.Id] = @{ Item = $i; Orig = $orig }
            }
            if ((Test-ItemApplied $i) -eq 'ok') { continue }
            $r = Set-ItemApplied $i
            Write-RunLog ("  {0,-8} {1}" -f $r, (Get-ItemLabel $i))
        }
        catch { Write-RunLog ("  FAILED   {0} : {1}" -f (Get-ItemLabel $i), $_.Exception.Message) }
    }
    Save-State $state

    # 3. Temp Unlock: clear the OneSettings cache so Gaming Services gets a fresh copy (it
    #    needs it to provision save folders). A running DiagTrack is restarted only when
    #    the user approved it for this run.
    if ($Config -and $Config.Unlocked) {
        try {
            $ds = Join-Path $env:ProgramData 'Microsoft\Diagnosis\DownloadedSettings'
            $dt = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
            if ($dt -and $dt.Status -ne 'Stopped' -and $script:AllowStop) { Stop-Service -Name DiagTrack -Force -ErrorAction SilentlyContinue; $dt.Refresh() }
            if (Test-Path -LiteralPath $ds) { Get-ChildItem -LiteralPath $ds -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
            if ($dt -and $dt.Status -eq 'Stopped') {
                Start-Service -Name DiagTrack -ErrorAction SilentlyContinue
                Write-RunLog '  OneSettings cache cleared; DiagTrack started'
            }
            else {
                Write-RunLog '  OneSettings cache cleared. DiagTrack was already running: restart Windows (or restart'
                Write-RunLog '  "Connected User Experiences and Telemetry" in Services yourself) so it downloads fresh settings.'
                $script:PendingRestart += 'DiagTrack (fresh OneSettings)'
            }
        }
        catch { Write-RunLog "  FAILED   OneSettings refresh: $($_.Exception.Message)" }
    }

    if ($Config -and $Config.Keeps -notcontains 'OneDrive' -and (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)) {
        if ($script:AllowStop) { Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Write-RunLog '  closed   OneDrive' }
        else { Write-RunLog '  OneDrive is still running. Quit it from its tray icon; it will not start again.' }
    }
    if ($Config) {
        try { Remove-CortanaApp } catch { Write-RunLog "  FAILED   Cortana removal: $($_.Exception.Message)" }
    }
    try { Sync-WingetTelemetry -Off:([bool]$Config) } catch { Write-RunLog "  FAILED   winget telemetry: $($_.Exception.Message)" }
    if ($Config -and $Config.NoSearch) {
        $sp = @(Get-Process -Name SearchApp, SearchUI, SearchHost -ErrorAction SilentlyContinue)
        if ($sp.Count) {
            if ($script:AllowStop) { $sp | Stop-Process -Force -ErrorAction SilentlyContinue; Write-RunLog '  closed   Windows Search UI (blocked from starting again)' }
            else { $script:PendingRestart += 'Windows Search UI' }
        }
    }
    if ((Test-NoEdge $Config) -and (Get-EdgeInstalled)) {
        try { Invoke-RemoveEdgeSystem -FromEnforce } catch { Write-RunLog "  FAILED   Edge removal: $($_.Exception.Message)" }
    }

    # 4. Owned state
    try { Sync-Firewall $desired } catch { Write-RunLog "  FAILED   firewall sync: $($_.Exception.Message)" }
    try { Sync-Hosts $desired } catch { Write-RunLog "  FAILED   hosts: $($_.Exception.Message)" }

    if ($script:PendingRestart.Count) {
        Write-RunLog ('  RESTART WINDOWS to finish. Still running until then (not approved to stop): {0}' -f (($script:PendingRestart | Select-Object -Unique) -join ', '))
    }
}
