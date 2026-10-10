# Telemetry & GDID Blocker - Runner.ps1
# Install folder, scheduled tasks, stop approval, run logs and running as SYSTEM / as the user.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

# ---------------------------------------------------------------------------
# Foreground helpers (admin)
# ---------------------------------------------------------------------------
function Protect-InstallDir {
    # The SYSTEM tasks run the script from this folder, so only SYSTEM and Administrators may
    # write to it. ProgramData lets standard users create files by default; this removes that,
    # and resets anything a non-admin may have placed there.
    try {
        $sys = New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'
        $adm = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'
        $usr = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-545'
        $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $none = [Security.AccessControl.PropagationFlags]::None
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetOwner($adm)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sys, 'FullControl', $inh, $none, 'Allow')))
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($adm, 'FullControl', $inh, $none, 'Allow')))
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($usr, 'ReadAndExecute', $inh, $none, 'Allow')))
        Set-Acl -LiteralPath $InstallDir -AclObject $acl
        if (Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue) {
            & icacls.exe (Join-Path $InstallDir '*') /reset /T /C /Q | Out-Null
        }
    }
    catch { Write-WarnBlock 'INSTALL FOLDER' @("Could not lock down $InstallDir : $($_.Exception.Message)") }
}

function Install-Self {
    if (-not (Test-Path -LiteralPath $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir | Out-Null }
    Protect-InstallDir
    # Copies the script and its Lib folder, unless this already is the installed copy. The Lib
    # folder is replaced as a whole so no file from an older version is left to be loaded.
    if ((Resolve-Path -LiteralPath $MainScript).Path -ne $InstalledScript) {
        Copy-Item -LiteralPath $MainScript -Destination $InstalledScript -Force
        if (Test-Path -LiteralPath $InstalledLib) { Remove-Item -LiteralPath $InstalledLib -Recurse -Force }
        Copy-Item -LiteralPath $LibDir -Destination $InstalledLib -Recurse -Force
    }
}

function Get-TaskAction {
    param([string]$InternalAction, [string]$Label)
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Internal {1}' -f $InstalledScript, $InternalAction
    if ($Label) { $arg += " -RunLabel $Label" }
    return New-ScheduledTaskAction -Execute $ps -Argument $arg
}

function Register-EnforceTasks {
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
    $boot = New-ScheduledTaskTrigger -AtStartup
    $boot.Delay = 'PT2M'
    Register-ScheduledTask -TaskPath $TaskFolder -TaskName $BootTask -Action (Get-TaskAction 'EnforceBoot') `
        -Trigger $boot -Principal $principal -Settings $settings -Force | Out-Null
    # Sign-in run: user hives are loaded, so per-user settings reach every profile.
    $logon = New-ScheduledTaskTrigger -AtLogOn
    $logon.Delay = 'PT1M'
    Register-ScheduledTask -TaskPath $TaskFolder -TaskName $LogonTask -Action (Get-TaskAction 'Enforce') `
        -Trigger $logon -Principal $principal -Settings $settings -Force | Out-Null
}

function Get-StopCandidates {
    # What an Enforce run would have to stop or close to take effect without a restart.
    param([hashtable]$Config)
    $c = @()
    $items = if ($Config) { Get-DesiredItems $Config } else { @($Catalog | Where-Object { $_.Kind -eq 'ServiceOn' }) }
    foreach ($i in $items) {
        if ($i.Kind -notin 'Service', 'ServiceOn') { continue }
        foreach ($svc in @(Get-Service -Name $i.Name, "$($i.Name)_*" -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Stopped' })) {
            if ($Config -and $i.Kind -eq 'ServiceOn') { continue }
            $c += "service $($svc.Name)"
        }
    }
    if ($Config) {
        if ((Test-NoEdge $Config) -and (Get-EdgeInstalled) -and (Get-Process -Name msedge -ErrorAction SilentlyContinue)) { $c += 'Microsoft Edge (open windows close)' }
        if ($Config.Keeps -notcontains 'OneDrive' -and (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)) { $c += 'OneDrive' }
        if (Get-Process -Name Cortana -ErrorAction SilentlyContinue) { $c += 'Cortana (removed)' }
        if ($Config.NoSearch -and (Get-Process -Name SearchApp, SearchUI, SearchHost -ErrorAction SilentlyContinue)) { $c += 'Windows Search UI (Start search box)' }
        if ($Config.Unlocked -and (Get-Service -Name DiagTrack -ErrorAction SilentlyContinue).Status -eq 'Running') { $c += 'DiagTrack (restarted to fetch fresh OneSettings)' }
    }
    return ,@($c | Select-Object -Unique)
}

function Show-HelloWarning {
    Write-Host ''
    Write-Host '  WARNING: WINDOWS HELLO' -ForegroundColor Yellow
    foreach ($l in @(
        'Every tier turns off Windows Hello (PIN, fingerprint, face) unless you keep it.'
        'You will sign in with your account PASSWORD instead. Make sure you know it first.'
        'A passwordless Microsoft account must have its password turned back on at'
        'account.microsoft.com/security first, or you can be locked out of Windows.'
        'Existing PINs are not deleted (Settings > Accounts > Sign-in options).'
        'To keep Hello: press Ctrl+C now and re-run with -KeepHello.'
    )) { Write-Host "    $l" }
}

function Show-HelloNotice {
    # Shown once at startup, before anything runs. Informational only: no prompt.
    $script:HelloAck = $true
    if ($KeepHello) { return }
    $cfg = Get-Config
    if ($cfg -and $cfg.Keeps -notcontains 'Hello') { return }   # already off from a previous Apply
    Show-HelloWarning
}

function Move-CursorToBottom {
    # Puts the next prompt near the bottom of the window (no-op if already past it).
    param([int]$LinesFromBottom = 2)
    try {
        $ui = $Host.UI.RawUI
        $target = $ui.WindowPosition.Y + $ui.WindowSize.Height - $LinesFromBottom
        $pos = $ui.CursorPosition
        if ($pos.Y -lt $target) { $pos.X = 0; $pos.Y = $target; $ui.CursorPosition = $pos }
    }
    catch { }
}

function Get-Prefs {
    $p = Read-JsonFile $PrefsPath
    return @{ AlwaysStop = [bool]($p -and $p.PSObject.Properties['AlwaysStop'] -and $p.AlwaysStop) }
}

function Set-AlwaysStop {
    # Saves (or clears) "always allow stopping services and closing programs".
    param([bool]$On)
    if (-not (Test-Path -LiteralPath $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir | Out-Null; Protect-InstallDir }
    Write-JsonFile $PrefsPath @{ AlwaysStop = $On }
}

function Request-StopApproval {
    # Asked once when the script starts, unless "always" was saved (Options > A turns it
    # off again). -StopNow pre-approves; -Force alone (unattended) means no. The startup and
    # sign-in tasks never stop anything, whatever is saved here.
    if ($StopNow) { return $true }
    if ($Force) { return $false }
    if ((Get-Prefs).AlwaysStop) { return $true }
    Write-Host ''
    Write-Host '  STOPPING SERVICES AND PROGRAMS' -ForegroundColor Cyan
    Write-Host '    Changes take effect immediately only if running services can be stopped and'
    Write-Host '    programs closed (Microsoft Edge, OneDrive). Save anything open in them first.'
    Write-Host '    If you say no, nothing is stopped and Windows must be restarted to finish.'
    Write-Host ''
    Write-Host '    Y = yes this time   N = no   A = always: yes, and don''t ask again (undo in Options)'
    Move-CursorToBottom 3
    Write-Rule
    $a = (Read-Host '  Allow this script to stop services and close programs? [y/N/a]').Trim()
    if ($a -match '^(a|always)$') {
        try { Set-AlwaysStop $true } catch { Write-Host '    Could not save the preference; asking again next time.' -ForegroundColor Yellow }
        return $true
    }
    return ($a -match '^(y|yes)$')
}

function Confirm-Stop {
    # Uses the answer given at startup; never prompts again.
    param([string[]]$Items)
    if (-not $Items -or -not $Items.Count) { return $false }
    return [bool]$script:StopApproved
}

function Request-Restart {
    # After a run the user did not approve stopping for: if anything is waiting on a
    # restart, say so and offer to restart Windows now.
    param([switch]$Pending)
    $markers = 'RESTART WINDOWS to finish|DEFERRED:|Edge is open, so it was not removed|OneDrive is still running'
    if (-not $Pending -and -not ((Test-Path -LiteralPath $LogPath) -and (Select-String -LiteralPath $LogPath -Pattern $markers -Quiet))) { return }
    Write-Host ''
    Write-Host '  Some changes finish only after Windows restarts (see the log above).' -ForegroundColor Yellow
    if ($Force) { Write-Host '  Restart Windows when convenient to finish.' -ForegroundColor Yellow; return }
    if ((Read-Host '  Restart Windows now? Save your work first. [y/N]') -match '^(y|yes)$') { Restart-Computer -Force }
    else { Write-Host '  Restart Windows when convenient to finish.' -ForegroundColor Yellow }
}

function Save-RunLog {
    # Copies the run's log to Logs\<date>-<action>.log, keeps the newest 30, returns the path.
    param([string]$Action)
    if (-not (Test-Path -LiteralPath $LogPath)) { return $LogPath }
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
        $dest = Join-Path $LogDir ('{0}-{1}.log' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), $Action)
        Copy-Item -LiteralPath $LogPath -Destination $dest -Force
        Get-ChildItem -LiteralPath $LogDir -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30 |
            Remove-Item -Force -ErrorAction SilentlyContinue
        return $dest
    }
    catch { return $LogPath }
}

function Remove-InstallKeepLogs {
    # Uninstall: removes everything in the install folder except the Logs history and
    # saved preferences.
    foreach ($c in @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)) {
        if ($c.Name -in 'Logs', 'prefs.json') { continue }
        Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-AsSystem {
    param([string]$InternalAction, [int]$TimeoutSeconds = 600, [switch]$AllowStop, [int]$Expected = 0, [string]$Label)
    if (-not $Label) { $Label = $InternalAction }
    Install-Self
    if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
    Remove-Item -LiteralPath $StopFlag -Force -ErrorAction SilentlyContinue
    if ($AllowStop) { Set-Content -LiteralPath $StopFlag -Value (Get-Date -Format o) -Encoding ASCII }
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
    Register-ScheduledTask -TaskPath $TaskFolder -TaskName $RunTask -Action (Get-TaskAction $InternalAction $Label) `
        -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskPath $TaskFolder -TaskName $RunTask
    # Live progress: one bar that updates in place, plus any failures/warnings as they occur.
    # The full step-by-step log stays in $LogPath.
    Write-Section 'PROGRESS'
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $done = $false
    $shown = 0; $steps = 0
    $alerts = New-Object System.Collections.ArrayList
    $counts = [ordered]@{}
    # Progress uses the shared bar (Write-InlineProgress). With a known step count it follows
    # the steps in the log; without one it creeps toward 90% over time.
    $start = Get-Date
    $tick = 0; $current = 'starting...'
    try {
        Write-InlineProgress 0 100 $current
        while ((Get-Date) -lt $deadline -and -not $done) {
            Start-Sleep -Milliseconds 100
            $tick++
            if ($tick % 2 -eq 0 -and (Test-Path -LiteralPath $LogPath)) {
                $lines = $null
                try { $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction Stop) } catch { }
                if ($lines) {
                    for ($i = $shown; $i -lt $lines.Count; $i++) {
                        $ln = [string]$lines[$i]
                        if ($ln -match '== DONE ==') { $done = $true; continue }
                        if ($ln -match '^--- ') { continue }
                        $steps++
                        $body = $ln -replace '^\d\d:\d\d:\d\d\s+', ''
                        $verb = ($body -split '\s+')[0]
                        if ($verb -cin 'set', 'disabled', 'enabled', 'added', 'removed', 'restored', 'cleared', 'closed', 'hosts', 'emptied') {
                            if ($counts.Contains($verb)) { $counts[$verb]++ } else { $counts[$verb] = 1 }
                        }
                        if ($body -cmatch '^FAILED\b|^ERROR:' -or $body -match 'RESTART WINDOWS|DEFERRED|still running|SKIPPED|not removed|Quit it') { [void]$alerts.Add($body) }
                        $current = $body
                    }
                    $shown = $lines.Count
                }
            }
            if ($Expected -gt 0) { Write-InlineProgress ([Math]::Min($steps, $Expected)) $Expected $current }
            else { Write-InlineProgress (90 * (1 - [Math]::Exp(-((Get-Date) - $start).TotalSeconds / 4))) 100 $current }
        }
    }
    finally {
        if ($done) { Write-InlineProgress -Keep -Label 'done' } else { Write-InlineProgress -Keep -Unfinished }
    }
    Write-Host ''
    Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $RunTask -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StopFlag -Force -ErrorAction SilentlyContinue
    if ($done) {
        Write-Host ''
        $sum = @($counts.Keys | ForEach-Object { if ($_ -eq 'hosts') { 'hosts file updated' } else { '{0} {1}' -f $counts[$_], $_ } })
        if ($sum.Count) { Write-Host ('    Changes: ' + ($sum -join ', ')) } else { Write-Host '    No changes needed: everything was already in place.' }
        $fails = @($alerts | Where-Object { $_ -cmatch '^FAILED\b|^ERROR:' })
        $warns = @($alerts | Where-Object { $_ -cnotmatch '^FAILED\b|^ERROR:' })
        foreach ($f in $fails) { Write-Host ('    ' + $f) -ForegroundColor Red }
        foreach ($w in $warns) { Write-Host ('    ' + $w) -ForegroundColor Yellow }
        $saved = Save-RunLog $Label
        if ($fails.Count) { Write-Host ("    Finished with {0} failure(s). Full log: {1}" -f $fails.Count, $saved) -ForegroundColor Yellow }
        else { Write-Host ("    Finished. Full log: {0}" -f $saved) -ForegroundColor Green }
    }
    if (-not $done) { Write-WarnBlock 'NO COMPLETION REPORTED' @(('The SYSTEM task did not report completion in time. Check {0} and run Status.' -f $LogPath)) }
}

function Invoke-AsUser {
    # Runs credential cleanup inside the interactive user's own logon session.
    param($User)
    $script = Join-Path $InstallDir 'wipe-user.ps1'
    $body = @'
$t = & cmdkey.exe /list 2>$null | ForEach-Object { if ($_ -match '^\s*Target:\s*(.+?)\s*$' -and $Matches[1] -match 'didlogical|SSO_POP_Device') { $Matches[1] } }
foreach ($x in @($t)) { & cmdkey.exe "/delete:$x" | Out-Null }
'@
    [IO.File]::WriteAllText($script, $body, (New-Object Text.UTF8Encoding $false))
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script)
    $principal = New-ScheduledTaskPrincipal -UserId $User.Name -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskPath $TaskFolder -TaskName 'Wipe user' -Action $action -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskPath $TaskFolder -TaskName 'Wipe user'
    try {
        foreach ($k in 1..50) { Write-InlineProgress $k 50 'clearing device credentials in your session...'; Start-Sleep -Milliseconds 100 }
    }
    finally { Write-InlineProgress -Clear }
    Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName 'Wipe user' -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue
    Write-Field 'User session' 'device credentials cleared (didlogical / SSO_POP_Device)'
}
