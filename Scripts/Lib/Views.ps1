# Telemetry & GDID Blocker - Views.ps1
# Options, tier comparison and Status screens.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

function Write-Paged {
    # Prints @(text, colour) pairs, pausing when a page fills the window.
    param([object[]]$Lines)
    $page = 40
    try { $page = [Math]::Max(10, $Host.UI.RawUI.WindowSize.Height - 3) } catch { }
    $n = 0
    foreach ($l in $Lines) {
        if ($l[1]) { Write-Host $l[0] -ForegroundColor $l[1] } else { Write-Host $l[0] }
        $n++
        if ($n -ge $page -and $n -lt $Lines.Count) {
            [void](Read-Host '  -- more: press Enter --')
            $n = 0
        }
    }
}

function Show-TierDetail {
    param([string]$Tier)
    $n = @($TierInfo.Keys).IndexOf($Tier) + 1
    $color = @{ Standard = 'Green'; Gaming = 'Cyan'; Maximum = 'Yellow'; Stripped = 'Red' }[$Tier]
    $outLines = New-Object System.Collections.ArrayList
    function Add-L([string]$t, [string]$c = '') { [void]$outLines.Add(@($t, $c)) }
    Add-L ''
    Add-L ("[{0}] {1}" -f $n, $Tier.ToUpper()) $color
    if ($TierInfo[$Tier].UseCase) {
        Add-L ''
        Add-L '    Who it is for:' 'Cyan'
        foreach ($l in $TierInfo[$Tier].UseCase) { Add-L "      $l" }
        Add-L ''
        Add-L '    What it changes:' 'Cyan'
    }
    if ($TierInfo[$Tier].Base) { Add-L "    $($TierInfo[$Tier].Base)" }
    foreach ($l in $TierInfo[$Tier].Adds) {
        if ($l.StartsWith('  ')) { Add-L "      $($l.Trim())" } else { Add-L "    + $l" }
    }
    Add-L ''
    Add-L '    What it disables:' 'Red'
    foreach ($l in $TierInfo[$Tier].Breaks) { Add-L "      $l" }
    Add-L ''
    Write-Paged $outLines.ToArray()
}

function Show-TierCompare {
    # Only rows that differ between tiers; everything shared is listed underneath.
    # Pipe-delimited: label|Standard|Gaming|Maximum|Stripped. A single field is a heading.
    $rows = @(
        'GDID'
        'GDID creation (personal sign-in)|Allowed|Allowed|Blocked|Blocked'
        'Device graph / Phone Link|Allowed|Blocked|Blocked|Blocked'
        'TELEMETRY'
        'Telemetry service (DiagTrack)|Blocked|Running|Blocked|Blocked'
        'Diagnostic data level|Lowest*|Required|Lowest*|Lowest*'
        'Diagnostic uploads|Blocked|Mostly|Blocked|Blocked'
        'OneSettings remote config|Mostly|Allowed|Blocked|Blocked'
        'ECS remote config (Teams/Edge/Office)|Allowed|Blocked|Blocked|Blocked'
        'Settings sync between PCs|Allowed|Blocked|Blocked|Blocked'
        'SECURITY AND UPDATES'
        'Defender cloud protection|Allowed|Blocked|Blocked|Blocked'
        'Delivery Optimization cloud|Allowed|Allowed|Blocked|Blocked'
        'Windows Update|Allowed|Allowed|Allowed|Blocked'
        'SmartScreen opt-out available|Yes|Yes|No|No'
        'STILL WORKS'
        'Microsoft Store / Xbox / Game Pass|Partly|Yes|No|No'
        'Personal Microsoft account logon|Yes|Yes|No|No'
    )
    $w = 40
    Write-Host ''
    Write-Host (('  {0,-' + $w + '}') -f 'COMPARE THE TIERS') -ForegroundColor Cyan -NoNewline
    foreach ($h in @('Standard|Green', 'Gaming|Cyan', 'Maximum|Yellow', 'Stripped|Red')) {
        $hp = $h.Split('|'); Write-Host ('{0,-10}' -f $hp[0]) -ForegroundColor $hp[1] -NoNewline
    }
    Write-Host ''
    Write-Host ('  ' + ('-' * ($w + 40)))
    foreach ($line in $rows) {
        $r = $line.Split('|')
        if ($r.Count -eq 1) { Write-Host ('  ' + $r[0]) -ForegroundColor Cyan; continue }
        Write-Host (('    {0,-' + ($w - 2) + '}') -f $r[0]) -NoNewline
        $yesNo = ($r[0] -like '*opt-out*') -or ($r[0] -in 'Microsoft Store / Xbox / Game Pass', 'Personal Microsoft account logon')
        for ($i = 1; $i -le 4; $i++) {
            $v = $r[$i]
            if ($yesNo) { $c = @{ Yes = 'Green'; Partly = 'Yellow'; No = 'Red' }[$v] }
            else { $c = @{ Blocked = 'Green'; 'Lowest*' = 'Green'; Mostly = 'Yellow'; Required = 'Yellow'; Running = 'Yellow'; Allowed = 'White' }[$v] }
            if (-not $c) { $c = 'White' }
            Write-Host ('{0,-10}' -f $v) -ForegroundColor $c -NoNewline
        }
        Write-Host ''
    }
    Write-Host ('  ' + ('-' * ($w + 40)))
    Write-Host '  SAME ON EVERY TIER' -ForegroundColor Cyan
    Write-Host '    Blocked: Spotlight and suggestions, Widgets, web search in Start, Copilot, Recall,'
    Write-Host '    Windows 11 AI features, location, automatic time zone, Windows Hello, OneDrive,'
    Write-Host '    Edge sign-in/sync, SmartScreen (opt-out at Standard and Gaming), error reports.'
    Write-Host '    Removed: Microsoft Edge, Cortana.'
    Write-Host '    Kept: WebView2, local crash dumps, activation, time sync, winget (its telemetry is off).'
    Write-Host ''
    Write-Host '  Green = blocked / works   Yellow = partly   White = allowed   Red = does not work'
    Write-Host '  * Lowest = Security on LTSC/Enterprise/Education, Required on Home/Pro.'
    Write-Host '  Most rows can be relaxed with a -Keep switch (see Switches).'
    Write-Host ''
}

function Show-TierSwitches {
    $w = 20
    Write-Section 'KEEP SWITCHES' '(leave these working)'
    Write-Field '-KeepGaming'      'Microsoft Store, Xbox / Xbox Live / Game Pass (automatic in Gaming)' 'White' $w -Key
    Write-Field '-KeepOffice'      'Office cloud features: Designer, Editor, online templates, Teams remote config' 'White' $w -Key
    Write-Field '-KeepDevTools'    'Visual Studio / VS Code / Application Insights / App Center hosts' 'White' $w -Key
    Write-Field '-KeepPhoneLink'   'Phone Link, Nearby Sharing, cross-device clipboard (GDID device graph; not needed at Standard)' 'White' $w -Key
    Write-Field '-KeepVoice'       'voice typing, voice access, online speech recognition' 'White' $w -Key
    Write-Field '-KeepSmartScreen' 'SmartScreen reputation lookups (Standard and Gaming only)' 'White' $w -Key
    Write-Field '-KeepLocation'    'location service and automatic time zone' 'White' $w -Key

    Write-Section 'OFF BY DEFAULT' '(every tier; Keep switch to opt out)'
    Write-Field '-KeepHello'       'Windows Hello PIN / biometrics. Know your account PASSWORD first.' 'White' $w -Key
    Write-Field '-KeepOneDrive'    'OneDrive sync client (files stay on disk)' 'White' $w -Key
    Write-Field '-KeepEdgeSync'    'Edge sign-in, sync, startup boost, background mode' 'White' $w -Key

    Write-Section 'REMOVED BY DEFAULT' '(every tier)'
    Write-Field '-KeepEdge'        'Microsoft Edge. WebView2 is always kept.' 'White' $w -Key
    Write-Field 'Cortana'          'no opt-out; reinstall from the Microsoft Store if wanted' 'White' $w -Key

    Write-Section 'PERSONAL MICROSOFT ACCOUNTS' '(blocked at Maximum and Stripped)'
    Write-Field '-KeepAccounts'    'leave personal Microsoft accounts working (a GDID is then created)' 'White' $w -Key
    Write-Field '-KeepDevTools'    'also lets VS / VS Code / GitHub sign in through the browser, no GDID' 'White' $w -Key
    Write-Note @('Work/school (Entra ID) accounts are never affected.')

    Write-Section 'OPT-IN' '(any tier)'
    Write-Field '-DisableSearch'   'Windows Search indexer and Start search box off; offers Everything / Open-Shell' 'White' $w -Key
    Write-Field '-BlockGpuTelemetry' 'NVIDIA / AMD / Intel telemetry off (driver updates untouched)' 'White' $w -Key

    Write-Section 'ALWAYS'
    Write-Field 'Blocked'          'Spotlight and suggestions; app telemetry opt-outs (Office, VS, .NET, PowerShell)' 'White' $w -Key
    Write-Field 'Never touched'    'local crash dumps, activation, time sync, winget (except its telemetry), WebView2' 'White' $w -Key
}

function Show-Options {
    # Non-interactive (redirected output): print everything. Interactive: a small menu.
    $interactive = $false
    try { $interactive = -not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected } catch { }
    if (-not $interactive) {
        Show-TierCompare
        foreach ($t in $TierInfo.Keys) { Show-TierDetail $t }
        Show-TierSwitches
        return
    }
    while ($true) {
        Clear-Host
        Show-Banner -NoIntro
        Write-Host ''
        Write-Host '  PROGRAM OPTIONS AND SWITCHES' -ForegroundColor Cyan
        Write-MenuItem 'C' 'Compare'  'all four tiers side by side'
        Write-MenuItem '1' 'Standard' 'what Standard changes and disables'
        Write-MenuItem '2' 'Gaming'   'what Gaming changes and disables'
        Write-MenuItem '3' 'Maximum'  'what Maximum changes and disables'
        Write-MenuItem '4' 'Stripped' 'what Stripped changes and disables'
        Write-MenuItem 'S' 'Switches' 'switches and opt-in options'
        Write-Host ''
        Write-Host '  PREFERENCES' -ForegroundColor Cyan
        $always = (Get-Prefs).AlwaysStop
        $stopTxt = if ($always) { 'ON: services stopped and programs closed without asking (A turns off)' } else { 'OFF: asked each time the script starts (A turns on)' }
        Write-MenuItem 'A' 'Always stop' $stopTxt
        Move-CursorToBottom 5
        Write-MenuItem 'B' 'Back'         'return to the main menu'
        Write-Host ''
        Write-Rule
        $c = (Read-Host '  Choose an option').Trim().ToUpper()
        $map = @{ '1' = 'Standard'; '2' = 'Gaming'; '3' = 'Maximum'; '4' = 'Stripped' }
        if ($c -in 'B', 'Q', '') { return }
        if ($c -eq 'A') {
            try { Set-AlwaysStop (-not $always) }
            catch { Write-Host '    Could not save: run the script as administrator.' -ForegroundColor Yellow; Start-Sleep -Seconds 2 }
            continue
        }
        Clear-Host
        if ($c -eq 'C') { Show-TierCompare }
        elseif ($map.ContainsKey($c)) { Show-TierDetail $map[$c] }
        elseif ($c -eq 'S') {
            Write-Host ''
            Write-Host "  $ScriptName v$ScriptVersion" -ForegroundColor Cyan -NoNewline
            Write-Host '   SWITCHES AND OPT-IN OPTIONS' -ForegroundColor White
            Write-Rule
            Show-TierSwitches
        }
        else { continue }
        Move-CursorToBottom 3
        Write-Rule
        [void](Read-Host '  Press Enter to go back')
    }
}

function Write-EnvironmentSummary {
    # -Brief (used by Apply) leaves out the modified-build notes so Apply fits in the window;
    # Status shows them in full.
    param([switch]$Brief)
    $ed = Get-WindowsEdition
    Write-Section 'SYSTEM'
    Write-Field 'Edition' $ed.Label
    if ($ed.Class -eq 'Enterprise') { Write-Field 'Telemetry floor' 'Security (0) - honoured on this edition' 'Green' }
    else {
        Write-Field 'Telemetry floor' 'Required (1) - Home/Pro ignores Security (0)' 'Yellow'
        Write-Note @('Enterprise-only policies are covered by per-user settings and the hosts/firewall blocks.')
    }
    $mod = Get-ModifiedBuild
    $isServer = ($ed.Id -match '^Server')
    # Windows 10 in support: LTSC 2019 (17763), LTSC 2021 (19044). Everything
    # else on Windows 10 (Home, Pro, Education, non-LTSC Enterprise, ESU, LTSB 2015/2016) is treated as end of life.
    $unsupported10 = (-not $isServer) -and $ed.Build -lt 22000 -and ((-not $ed.Ltsc) -or $ed.Build -lt 17763)
    # Windows 11 treated as in support (releases ending within weeks count as ended):
    #   Home/Pro:               25H2 (26200) and 26H1 (28000) or later. 24H2 (26100) ends 2026-10-13.
    #   Enterprise/Education:   24H2 (26100) or later. 23H2 (22631) ends 2026-11-10.
    #   LTSC 2024 (26100):      supported.
    # Update these cutoffs as Microsoft retires releases.
    $unsupported11 = $false
    if (-not $isServer -and $ed.Build -ge 22000) {
        if ($ed.Ltsc)                       { $unsupported11 = $ed.Build -lt 26100 }
        elseif ($ed.Class -eq 'Enterprise') { $unsupported11 = $ed.Build -lt 26100 }
        else                                { $unsupported11 = $ed.Build -lt 26200 }
    }
    if ($unsupported10 -or $unsupported11) {
        Write-Field 'Support' 'INSECURE AND UNSUPPORTED: no longer receives Microsoft security updates' 'Red'
        if ($unsupported10) { Write-Note @('Upgrade to Windows 10 Enterprise LTSC / IoT Enterprise LTSC, or a supported Windows 11 release.') 'Red' }
        else { Write-Note @('Install the current feature update or Windows 11 Enterprise LTSC.') 'Red' }
        Write-Note @('Applying as normal; problems on this version will not be fixed.') 'Red'
    }
    else { Write-Field 'Support' 'Supported' 'Green' }
    if ($mod.Name -or $mod.Removed.Count) {
        $what = @()
        if ($mod.Name) { $what += $mod.Name }
        if ($mod.Removed.Count) { $what += ('{0} removed' -f ($mod.Removed -join ', ')) }
        Write-Field 'Modified build' ($what -join '; ') 'Yellow'
        $notes = @('Community builds change Windows ahead of this script, so some settings may already be changed, removed or behave differently. Applying as normal.')
        if ($mod.Removed -contains 'Defender') { $notes += 'Without Defender, nothing scans for malware unless you installed another antivirus.' }
        if ($mod.Removed -contains 'Windows Update') { $notes += 'Without Windows Update, security patches come only from the build''s maintainer: keep it current.' }
        $notes += 'This script cannot tell whether a modified build is itself trustworthy. Only use builds from a source you trust.'
        $notes += 'Use Stripped only if Defender is gone and Windows Update is removed or paused.'
        if (-not $Brief) { Write-Note $notes }
    }
    if (Test-InsiderEnrolled) { Write-Field 'Insider' 'Windows Insider build: not supported; flights will stop' 'Yellow' }
    if (Test-MdmEnrolled) { Write-Field 'MDM' 'Enrolled: dmwappushservice is left running' 'Yellow' }
    if (-not (Test-StoreInstalled) -and $mod.Removed -notcontains 'Microsoft Store') { Write-Field 'Microsoft Store' 'Not installed' }
    try {
        $off = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
        if ($off.Count) {
            Write-Field 'Firewall' ('OFF ({0}): this script''s firewall rules do nothing' -f ($off -join ', ')) 'Yellow'
            Write-Note @('Hosts, services, policies and the IFEO executable blocks still apply.')
        }
    }
    catch { }
    $gone = @('DiagTrack', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'DoSvc') | Where-Object { -not (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$_") }
    if ($gone.Count) {
        Write-Field 'Removed services' ($gone -join ', ')
        Write-Note @('Removed by another tool; this script cannot recreate them. The Gaming tier and Temp Unlock need DiagTrack and the Xbox services.')
    }
}

function Show-Status {
    # Sets $script:StatusDrift to the number of drifted items, so the menu can offer to re-apply.
    param([switch]$FromMenu)
    $cfg = Get-Config
    $script:StatusDrift = 0
    $script:StatusGdid = $false
    Write-EnvironmentSummary

    Write-Section 'TIER'
    if ($null -eq $cfg) { Write-Field 'Tier' 'not applied' }
    else {
        $tc = @{ Standard = 'Green'; Gaming = 'Cyan'; Maximum = 'Yellow'; Stripped = 'Red' }[$cfg.Tier]
        Write-Field 'Tier' $cfg.Tier $tc
        $keeps = 'none'
        if ($cfg.Keeps.Count) { $keeps = $cfg.Keeps -join ', ' }
        Write-Field 'Keeping' $keeps
        $lvl = Get-TelemetryLevel $cfg
        $lvlTxt = @{ 0 = 'Security (0)'; 1 = 'Required (1)'; 3 = 'Full (3) - Temp Unlock' }[[int]$lvl]
        Write-Field 'Diagnostic data' $lvlTxt
        if (Test-AccountsBlocked $cfg) { Write-Field 'Personal accounts' 'Blocked - no new GDID' 'Green' }
        else { Write-Field 'Personal accounts' 'Allowed - a GDID is created' 'Yellow' }
        if (Test-SmartScreenOff $cfg) { Write-Field 'SmartScreen' 'Off' } else { Write-Field 'SmartScreen' 'On' }
        $offs = @()
        foreach ($f in @(@('Hello', 'Hello'), @('OneDrive', 'OneDrive'), @('EdgeSync', 'Edge sign-in/sync'), @('Location', 'Location'))) { if ($cfg.Keeps -notcontains $f[0]) { $offs += $f[1] } }
        if ($cfg.NoSearch) { $offs += 'Windows Search' }
        if ($cfg.GpuTel) { $offs += 'GPU telemetry' }
        $offTxt = 'none'
        if ($offs.Count) { $offTxt = $offs -join ', ' }
        Write-Field 'Also off' $offTxt
        if (Test-NoEdge $cfg) {
            if (Get-EdgeInstalled) { Write-Field 'Microsoft Edge' 'STILL INSTALLED - see the Apply log' 'Yellow' }
            else { Write-Field 'Microsoft Edge' 'Removed (WebView2 kept)' 'Green' }
        }
        if ($cfg.Unlocked) { Write-Field 'Temp Unlock' 'ACTIVE: telemetry fully on until Relock or reboot' 'Yellow' }
        foreach ($t in @(@($BootTask, 'Startup task'), @($LogonTask, 'Sign-in task'))) {
            $task = Get-ScheduledTask -TaskPath $TaskFolder -TaskName $t[0] -ErrorAction SilentlyContinue
            if ($task) { Write-Field $t[1] ([string]$task.State) 'Green' }
            else { Write-Field $t[1] 'MISSING' 'Red' }
        }
        $desired = Get-DesiredItems $cfg
        $drift = @(); $na = 0; $ok = 0; $n = 0
        try {
            foreach ($i in $desired) {
                $n++
                Write-InlineProgress ($n - 1) $desired.Count ('checking ' + (Get-ItemLabel $i))
                $r = Test-ItemApplied $i
                if ($r -eq 'ok') { $ok++ } elseif ($r -eq 'n/a') { $na++ } else { $drift += $i }
            }
            Write-InlineProgress $n $desired.Count 'done'
        }
        finally { Write-InlineProgress -Clear }
        $dc = if ($drift.Count) { 'Yellow' } else { 'Green' }
        Write-Field 'Changes' ('{0} applied, {1} not present on this build, {2} drifted' -f $ok, $na, $drift.Count) $dc
        foreach ($i in $drift) { Write-Note @('drifted: ' + (Get-ItemLabel $i)) 'Yellow' }
        $script:StatusDrift = $drift.Count
        if ($drift.Count) {
            if ($FromMenu) { Write-Note @('Press A below to re-apply with the same choices, or sign out and in (the tasks re-apply).') 'Yellow' }
            else { Write-Note @('Re-apply with: Start.cmd -Action Apply (same tier and choices), or sign out and in.') 'Yellow' }
        }
    }

    Write-Section 'NETWORK'
    $probe = 'v10.events.data.microsoft.com'
    try {
        $addr = @([Net.Dns]::GetHostAddresses($probe) | ForEach-Object { $_.ToString() })
        $sink = @($addr | Where-Object { $_ -ne '0.0.0.0' -and $_ -ne '::' }).Count -eq 0
        if ($sink) { Write-Field 'Telemetry probe' "$probe is sinkholed" 'Green' }
        else { Write-Field 'Telemetry probe' ("$probe RESOLVES (" + ($addr -join ', ') + ')') 'Yellow' }
    }
    catch { Write-Field 'Telemetry probe' "$probe does not resolve" 'Green' }
    $wd = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($wd -and $wd.Status -eq 'Running') {
        try {
            $hits = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.ThreatName -match 'HostsFileHijack' })
            if ($hits.Count) { Write-Field 'Defender' 'Flagged the hosts file (HostsFileHijack): allow it in Protection history' 'Yellow' }
        }
        catch { }
    }

    Write-Section 'GDID' '(IdentityCRL LID)'
    $u = $null
    try { $u = Get-InteractiveUser } catch { }
    $sid = ''
    if ($u) { $sid = $u.Sid }
    $g = Get-GdidReport $sid
    foreach ($k in $g.Keys) { Write-Field $k $g[$k] }
    $script:StatusGdid = @($g.Values | Where-Object { $_ -ne 'none' }).Count -gt 0
    if ($cfg -and -not (Test-AccountsBlocked $cfg)) {
        Write-Note @('GDID creation is not blocked with these settings, so a GDID is expected here.')
    }
    if ($script:StatusGdid -and $FromMenu) { Write-Note @('Press W to wipe it.') 'Yellow' }
}
