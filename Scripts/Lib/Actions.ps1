# Telemetry & GDID Blocker - Actions.ps1
# Apply, Remove Edge, Temp Unlock / Relock, Roll back and Wipe.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

function Test-OneDriveFolderRedirect {
    $u = $null
    try { $u = Get-InteractiveUser } catch { }
    if (-not $u) { return $false }
    $p = Get-ItemProperty -LiteralPath "Registry::HKEY_USERS\$($u.Sid)\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    foreach ($n in 'Desktop', 'Personal', 'My Pictures') {
        if ($p.PSObject.Properties[$n] -and ([string]$p.$n) -match 'OneDrive') { return $true }
    }
    return $false
}

function Invoke-Apply {
    param([string]$T, [hashtable]$Opt)
    if (-not $T) { throw 'Specify -Tier Standard, Gaming, Maximum or Stripped.' }
    $Keeps = @($Opt.Keeps | Where-Object { $_ })
    if ($T -eq 'Gaming' -and $Keeps -notcontains 'Gaming') { $Keeps += 'Gaming' }
    Write-Host ''
    Write-EnvironmentSummary -Brief
    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain -and -not $Force) {
        throw 'This PC is domain-joined. Group Policy may fight these settings. Re-run with -Force to continue anyway.'
    }
    if (($T -in 'Maximum', 'Stripped') -and $Keeps -contains 'SmartScreen') {
        Write-WarnBlock 'SMARTSCREEN' @("$T has no SmartScreen opt-out; -KeepSmartScreen is ignored.")
        $Keeps = @($Keeps | Where-Object { $_ -ne 'SmartScreen' })
    }
    $smartOff = Test-SmartScreenOff @{ Tier = $T; Keeps = $Keeps }
    if ($TierRank[$T] -ge 2 -or $smartOff) {
        $wd = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        if ($wd -and $wd.Status -eq 'Running') {
            if ($T -eq 'Stripped' -and -not $Force) {
                throw 'Defender is running. The Stripped tier is for builds without Defender and Windows Update. Use Maximum, or re-run with -Force.'
            }
            if ($TierRank[$T] -ge 2 -and $smartOff) {
                $keepTxt = if ($T -eq 'Gaming') { '-KeepSmartScreen keeps SmartScreen only.' } else { "Neither can be kept at $T." }
                Write-WarnBlock 'SMARTSCREEN AND DEFENDER CLOUD' @("Both will be off: no reputation check on downloads and no cloud lookups for new malware. Defender still scans locally. $keepTxt")
            }
            elseif ($TierRank[$T] -ge 2) { Write-WarnBlock 'DEFENDER CLOUD' @('Defender cloud protection will be off: no cloud lookups for new malware. Defender still scans locally. SmartScreen stays on (-KeepSmartScreen).') }
            else { Write-WarnBlock 'SMARTSCREEN' @('SmartScreen will be off: no reputation check on downloaded programs. Defender cloud protection stays on. -KeepSmartScreen keeps it.') }
        }
    }
    if ($Keeps -contains 'Gaming' -and -not (Test-StoreInstalled)) {
        Write-Note @('Note: Microsoft Store is not installed. The Gaming settings are applied anyway and take effect once it is.')
    }
    if ($Keeps -contains 'Accounts' -and $T -notin 'Maximum', 'Stripped') { $Keeps = @($Keeps | Where-Object { $_ -ne 'Accounts' }) }
    if (Test-AccountsBlocked @{ Tier = $T; Keeps = $Keeps }) {
        $dep = Get-AccountDependents
        if ($dep.Contains('WindowsLogon')) {
            # The "Block Microsoft accounts" policy stops Microsoft-account logons: never apply over one.
            throw ("{0}. $T blocks personal Microsoft accounts and would lock them out. Switch to a local account first (Settings > Accounts > Your info > 'Sign in with a local account instead'), or re-run with -KeepAccounts." -f $dep['WindowsLogon'])
        }
        $lines = @("$T blocks personal Microsoft account sign-in, so no new GDID can be created. Work/school accounts are unaffected. To keep personal accounts, re-run with -KeepAccounts.")
        if ($dep.Count) {
            $lines += 'Found on this PC:'
            foreach ($k in $dep.Keys) { $lines += ('  - ' + $dep[$k]) }
            if (($dep.Contains('VisualStudio') -or $dep.Contains('VSCode')) -and $Keeps -notcontains 'DevTools') {
                $lines += '-KeepDevTools lets VS / VS Code sign in with a personal account through the browser, still without a GDID.'
            }
            if ($dep.Contains('Office') -or $dep.Contains('OneDrive') -or $dep.Contains('Store')) {
                $lines += 'Office, OneDrive and the Store sign in through Windows: a personal account there needs -KeepAccounts (a GDID is then created).'
            }
        }
        Write-WarnBlock 'PERSONAL MICROSOFT ACCOUNTS WILL BE BLOCKED' $lines
        if (-not $Force) {
            Write-Host ''
            if ((Read-Host '  Are you sure? [y/N]') -notmatch '^(y|yes)$') { Write-Host '    Cancelled.'; return }
        }
    }
    $noEdgeNow = ($Keeps -notcontains 'Edge')
    $prev = Get-Config
    $helloAlreadyOff = ($prev -and $prev.Keeps -notcontains 'Hello')
    if ($Keeps -notcontains 'Hello' -and -not $helloAlreadyOff -and -not $script:HelloAck) { Show-HelloWarning }
    if ($noEdgeNow -and (Get-EdgeInstalled)) {
        Write-WarnBlock 'MICROSOFT EDGE WILL BE REMOVED' @(
            "Tier $T uninstalls Microsoft Edge and blocks it from coming back. WebView2 is kept.",
            'Roll back does not reinstall Edge. To keep Edge, re-run with -KeepEdge.',
            'If Windows Update has updates pending, finish them first: removing Edge mid-update can cause update failure loops.')
    }
    if ($Keeps -notcontains 'OneDrive' -and (Test-OneDriveFolderRedirect)) {
        Write-WarnBlock 'ONEDRIVE FOLDERS' @('Desktop/Documents/Pictures are redirected into OneDrive. They stay there (on disk, no longer synced). Move them back first if you want them in your profile folders.')
    }
    $noEdge = $false
    if ($prev) { $noEdge = [bool]$prev.NoEdge }
    Install-Self
    $noSearch = [bool]$Opt.NoSearch
    Save-Config @{ Tier = $T; Keeps = $Keeps; Unlocked = $false; NoEdge = $noEdge; NoSearch = $noSearch; GpuTel = [bool]$Opt.GpuTel }
    Register-EnforceTasks
    $ok = Confirm-Stop (Get-StopCandidates (Get-Config))
    $expect = 0
    try { $expect = (Get-DesiredItems (Get-Config)).Count } catch { }
    Invoke-AsSystem 'Enforce' -AllowStop:$ok -Expected $expect -Label 'Apply'
    Write-Host ''
    Write-Host ''
    Write-Host "    Tier $T applied. It is re-applied at startup and sign-in; use Status to check for drift." -ForegroundColor Green
    if ($noSearch) { Request-SearchReplacements }
    if (-not $ok) { Request-Restart }
}

function Invoke-RemoveEdge {
    Write-Section 'REMOVE MICROSOFT EDGE'
    Write-Note @('Uninstalling Microsoft Edge with its own installer. WebView2 is left alone.',
        'Roll back does not reinstall Edge (get it from microsoft.com/edge if needed).')
    $cfg = Get-Config
    $cand = @()
    if (Get-Process -Name msedge -ErrorAction SilentlyContinue) { $cand += 'Microsoft Edge (open windows close)' }
    if ($cfg) { $cfg.NoEdge = $true; $cand += Get-StopCandidates $cfg }
    $ok = Confirm-Stop @($cand | Select-Object -Unique)
    Invoke-AsSystem 'RemoveEdge' -AllowStop:$ok -Label 'RemoveEdge'
    if ($cfg) {
        Save-Config $cfg
        Invoke-AsSystem 'Enforce' -AllowStop:$ok -Label 'Apply' -Expected ((Get-DesiredItems $cfg).Count)
    }
    if (-not $ok) { Request-Restart }
    if (-not $cfg) {
        Write-Host ''
        Write-Host '    No tier is applied, so nothing stops Edge coming back. Apply a tier to block its reinstall.' -ForegroundColor Yellow
    }
}

function Invoke-Reapply {
    # Re-applies the saved tier exactly as it was applied (same Keep switches and opt-ins),
    # without the Apply questions. Used to fix drift from the Status screen.
    $cfg = Get-Config
    if ($null -eq $cfg) { throw 'No tier is applied, so there is nothing to re-apply.' }
    Write-Section 'RE-APPLY'
    $k = if ($cfg.Keeps.Count) { ' (keeping ' + ($cfg.Keeps -join ', ') + ')' } else { '' }
    Write-Note @("Re-applying $($cfg.Tier)$k with the same options.")
    Register-EnforceTasks
    $ok = Confirm-Stop (Get-StopCandidates $cfg)
    Invoke-AsSystem 'Enforce' -AllowStop:$ok -Label 'Apply' -Expected ((Get-DesiredItems $cfg).Count)
    Write-Host ''
    Write-Host '    Re-applied. Run Status again to confirm nothing has drifted.' -ForegroundColor Green
    if (-not $ok) { Request-Restart }
}

function Invoke-TempUnlock {
    param([bool]$Unlock)
    $cfg = Get-Config
    if ($null -eq $cfg) { throw 'No tier is applied, so there is nothing to unlock or relock.' }
    if ($Unlock -and (Test-AccountsBlocked $cfg)) {
        Write-WarnBlock 'XBOX SIGN-IN STILL BLOCKED' @("$($cfg.Tier) blocks personal Microsoft accounts, so Xbox / Game Pass games still cannot sign in. Use the Gaming tier, or apply $($cfg.Tier) with -KeepAccounts.")
    }
    $cfg.Unlocked = $Unlock
    Save-Config $cfg
    $ok = Confirm-Stop (Get-StopCandidates $cfg)
    Invoke-AsSystem 'Enforce' -AllowStop:$ok -Label 'GameUnlock' -Expected ((Get-DesiredItems $cfg).Count)
    if (-not $ok) {
        if ($Unlock) {
            if ((Test-Path -LiteralPath $LogPath) -and (Select-String -LiteralPath $LogPath -Pattern 'DiagTrack was already running' -Quiet)) {
                Write-WarnBlock 'RESTART ONE SERVICE' @('Restarting Windows would end Temp Unlock, so instead restart "Connected User Experiences and Telemetry" in Services yourself before launching the game.')
            }
        }
        else { Request-Restart }
    }
    if ($Unlock) {
        Write-Section 'TEMP UNLOCK ACTIVE'
        Write-Field 'Telemetry' 'fully on (AllowTelemetry 3; DiagTrack and OneSettings unblocked)' 'Yellow'
        Write-Note @('Launch the game and stay in until it loads, syncs saves and connects online (e.g. Horizon Life), then choose Relock. Restarting Windows also relocks.')
    }
    else { Write-Host ''; Write-Host '    Relocked: your tier''s settings are back in place.' -ForegroundColor Green }
}

function Invoke-Rollback {
    Write-Section 'ROLL BACK'
    if (-not (Test-Path -LiteralPath $InstallDir)) { Write-Note @('Nothing to roll back: no tier is applied.'); return }
    Write-Note @('Restores the system from the backups taken before the first Apply, returning every recorded setting to its original state, and removes the hosts block, firewall rules and scheduled tasks.', 'Apps this script removed (Edge, Cortana) are not reinstalled.')
    if (-not $Force) {
        Write-Host ''
        if ((Read-Host '  Are you sure? [y/N]') -notmatch '^(y|yes)$') { Write-Host '    Cancelled.'; return }
    }
    $ok = Confirm-Stop (Get-StopCandidates $null)
    Invoke-AsSystem 'Rollback' -AllowStop:$ok -Label 'Rollback' -Expected ((Get-State).Count)
    $rollbackPending = (-not $ok) -and (Test-Path -LiteralPath $LogPath) -and (Select-String -LiteralPath $LogPath -Pattern 'RESTART WINDOWS to finish' -Quiet)
    foreach ($tn in $BootTask, $LogonTask) {
        Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue
    }
    try {
        $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
        $svc.GetFolder('\').DeleteFolder($TaskFolder.Trim('\'), 0)
    }
    catch { }
    $state = Get-State
    if ($state.Count -eq 0) {
        Remove-InstallKeepLogs
        Write-Host ''
        Write-Host '    Rolled back and uninstalled.' -ForegroundColor Green
        Write-Host ("    Logs kept in {0}" -f $LogDir)
    }
    else {
        Write-WarnBlock 'NOT EVERYTHING WAS RESTORED' @("Some items could not be restored (for example settings in a user profile that is not signed in). Their state is kept in $InstallDir; sign that user in and run Roll back again.")
    }
    if ($rollbackPending) { Request-Restart -Pending }
}

function Invoke-Wipe {
    $cfg = Get-Config
    $mint = Test-AccountsBlocked $cfg
    Write-Section 'WIPE THE LOCAL GDID'
    Write-Note @('Clears the stored device ID, device tokens, token caches, Windows Live device credentials and the telemetry machine ID.')
    if (-not $mint) {
        Write-WarnBlock 'A NEW GDID WILL BE CREATED' @(
            'Personal Microsoft account sign-in is not blocked, so Windows will create a new GDID the next time something signs in with a personal Microsoft account.',
            'Wiping only breaks continuity with the old ID; Microsoft may still link the two. Apply Maximum or Stripped (without -KeepAccounts) to stop new IDs.')
    }
    $u = Get-InteractiveUser
    if (-not $u) { throw 'No interactive user is signed in.' }
    Write-Section 'BEFORE'
    $b = Get-GdidReport $u.Sid; foreach ($k in $b.Keys) { $c = if ($b[$k] -eq 'none') { 'Green' } else { 'Yellow' }; Write-Field $k $b[$k] $c }
    Install-Self
    Write-JsonFile $WipePath @{ Sid = $u.Sid }
    Invoke-AsUser $u
    $rs = @(@('wlidsvc', 'TokenBroker', 'CDPSvc') + @(Get-Service -Name 'CDPUserSvc_*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) |
        Where-Object { (Get-Service -Name $_ -ErrorAction SilentlyContinue).Status -eq 'Running' } | ForEach-Object { "service $_ (restarted after the wipe)" })
    $ok = Confirm-Stop $rs
    Invoke-AsSystem 'WipeSystem' -AllowStop:$ok -Label 'Wipe' -Expected 12   # about one log line per item wiped
    $pend = Read-JsonFile $WipePath
    if ($pend -and $pend.PSObject.Properties['Pending'] -and $pend.Pending) {
        $how = if (Get-Config) { 'Restart Windows to finish (the startup task completes it).' } else { 'Restart Windows, then run Wipe again.' }
        Write-WarnBlock 'WIPE NOT FINISHED YET' @('Services holding the GDID are running and were not stopped. They are set to Disabled until the wipe completes.', $how)
        if (Get-Config) { Request-Restart -Pending }
        return
    }
    Write-Section 'AFTER'
    $a = Get-GdidReport $u.Sid; foreach ($k in $a.Keys) { $c = if ($a[$k] -eq 'none') { 'Green' } else { 'Yellow' }; Write-Field $k $a[$k] $c }
    if (-not (Get-Config)) {
        Remove-InstallKeepLogs
    }
}

function Read-Keeps {
    # Starts from what is saved with the applied tier: Enter keeps it, letters replace it,
    # '-' clears it. Saved keeps that do not exist at tier $T are dropped, with a note.
    param([string]$T)
    $saved = Get-SavedKeeps $T
    $avail = Get-AvailableKeeps $T
    Write-Host ''
    Write-Host '  KEEP WORKING' -ForegroundColor Cyan
    if ($avail -contains 'Gaming') { Write-MenuItem 'G' 'Gaming' 'Microsoft Store, Xbox, Game Pass' }
    Write-MenuItem 'O' 'Office'    'Office cloud features (Designer, Editor, templates, Teams remote config)'
    Write-MenuItem 'D' 'DevTools'  'VS / VS Code / Azure dev hosts (+ browser sign-in at Maximum/Stripped)'
    if ($avail -contains 'PhoneLink') { Write-MenuItem 'P' 'PhoneLink' 'Phone Link / Nearby Sharing (leaves GDID registration unblocked)' }
    Write-MenuItem 'V' 'Voice'     'voice typing / online speech'
    Write-MenuItem 'N' 'OneDrive'  'OneDrive sync'
    Write-MenuItem 'S' 'EdgeSync'  'Edge sign-in / sync'
    Write-MenuItem 'E' 'Edge'      'Microsoft Edge (otherwise uninstalled; WebView2 is always kept)'
    Write-MenuItem 'L' 'Location'  'location service and automatic time zone'
    if ($avail -contains 'Accounts') { Write-MenuItem 'A' 'Accounts' 'personal Microsoft accounts (Store, OneDrive, Office; GDID then created)' }
    if ($avail -contains 'SmartScreen') { Write-MenuItem 'W' 'SmartScreen' 'SmartScreen download / URL reputation checks' }
    Write-Host ''
    Write-Host '    Currently keeping: ' -NoNewline
    if ($saved.Kept.Count) { Write-Host ($saved.Kept -join ', ') -ForegroundColor Green } else { Write-Host 'nothing' }
    if ($saved.Dropped.Count) { Write-Host ('    Not available on {0}, dropped: {1}' -f $T, ($saved.Dropped -join ', ')) -ForegroundColor Yellow }
    if ($saved.HelloSaved -and -not $KeepHello) { Write-Host '    Windows Hello was kept last time; it is turned off this time unless you run with -KeepHello.' -ForegroundColor Yellow }
    Write-Host '    Enter keeps the current set. Type letters to replace it (e.g. OD), or - for none.'
    Move-CursorToBottom 3
    Write-Rule
    $in = (Read-Host '  Keep').Trim().ToUpper()
    if ($in -eq '') { $k = @($saved.Kept) }
    elseif ($in -eq '-') { $k = @() }
    else {
        $map = @{ G = 'Gaming'; O = 'Office'; D = 'DevTools'; P = 'PhoneLink'; V = 'Voice'; N = 'OneDrive'; S = 'EdgeSync'; E = 'Edge'; W = 'SmartScreen'; L = 'Location'; A = 'Accounts' }
        $k = @()
        foreach ($ch in $in.ToCharArray()) { $s = [string]$ch; if ($map.ContainsKey($s) -and $avail -contains $map[$s] -and $k -notcontains $map[$s]) { $k += $map[$s] } }
    }
    if ($KeepHello -and $k -notcontains 'Hello') { $k += 'Hello' }   # -KeepHello also applies to the menu
    return ,$k
}
