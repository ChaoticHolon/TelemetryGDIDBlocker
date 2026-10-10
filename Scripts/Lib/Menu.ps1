# Telemetry & GDID Blocker - Menu.ps1
# Main menu.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

function Write-MenuItem {
    param([string]$Key, [string]$Name, [string]$Desc = '')
    Write-Host '    ' -NoNewline
    Write-Host ("[{0}]" -f $Key) -ForegroundColor Yellow -NoNewline
    Write-Host (' {0,-12}' -f $Name) -ForegroundColor White -NoNewline
    if ($Desc) { Write-Host (' ' + $Desc) } else { Write-Host '' }
}

function Show-Menu {
    while ($true) {
        $cfgNow = Get-Config
        $gamingTier = ($cfgNow -and $cfgNow.Tier -eq 'Gaming')
        Clear-Host
        Show-Banner -NoIntro
        Write-Host ''
        Write-Host '  APPLY A TIER' -ForegroundColor Cyan
        Write-MenuItem '1' 'Standard'     'telemetry, Copilot/Recall, Hello, OneDrive, location off; Edge removed'
        Write-MenuItem '2' 'Gaming'       'Maximum blocking, but Store / Xbox / Game Pass just work'
        Write-MenuItem '3' 'Maximum'      '+ personal accounts (no GDID), device graph, remote config, SmartScreen'
        Write-MenuItem '4' 'Stripped'     '+ Windows Update and definition updates off (GhostSpectre-type builds)'
        Write-Host ''
        $gNote = if ($gamingTier) { '(Only needed for first launch or game errors)' } else { '(Not needed for Gaming tier)' }
        Write-Host '  MICROSOFT GAMING / XBOX ' -ForegroundColor Cyan -NoNewline; Write-Host $gNote
        Write-MenuItem 'G' 'Temp Unlock'  'game won''t start, sign in or sync saves? full telemetry + Xbox services on'
        Write-MenuItem 'L' 'Relock'       'end Temp Unlock now: telemetry blocked again, Xbox services as before'
        Write-Host ''
        Write-Host '  TOOLS' -ForegroundColor Cyan
        Write-MenuItem 'S' 'Status'       'check what is applied, drift and the current GDID'
        Write-MenuItem 'O' 'Options'      'view program options and switches, compare tiers'
        Write-MenuItem 'R' 'Remove Edge'  'uninstall Microsoft Edge (WebView2 is kept)'
        Write-MenuItem 'W' 'Wipe'         'wipe the local GDID'
        Write-MenuItem 'U' 'Roll back'    'restore system from backups to original state (does not reinstall apps)'
        Move-CursorToBottom 5
        Write-MenuItem 'Q' 'Quit'         'exit this script'
        Write-Host ''
        Write-Rule
        $c = (Read-Host '  Choose an option').Trim().ToUpper()
        if ($c -eq 'Q') { return }
        $tiers = @{ '1' = 'Standard'; '2' = 'Gaming'; '3' = 'Maximum'; '4' = 'Stripped' }
        $known = $tiers.ContainsKey($c) -or ($c -in 'S', 'O', 'G', 'L', 'R', 'W', 'U')
        if (-not $known) { continue }
        Clear-Host
        $skipPause = $false
        try {
            if ($tiers.ContainsKey($c)) {
                $t = $tiers[$c]
                Show-Banner -NoIntro -ExtraRows @(, @('Applying:', $t, 'Green'))
                $keeps = Read-Keeps $t
                $ns = [bool]$DisableSearch
                $gt = [bool]$BlockGpuTelemetry
                $cfgNow2 = Get-Config
                $curNs = [bool]($cfgNow2 -and $cfgNow2.NoSearch)
                $curGt = [bool]($cfgNow2 -and $cfgNow2.GpuTel)
                if (-not $ns -or -not $gt) {
                    Clear-Host
                    Show-Banner -NoIntro -ExtraRows @(, @('Applying:', $t, 'Green'))
                    Write-Host ''
                    Write-Host '  OPT-IN OPTIONS' -ForegroundColor Cyan
                    if (-not $ns) {
                        Write-Host '    Windows Search  ' -ForegroundColor White -NoNewline; Write-Host 'indexer and Start/taskbar search box off; offers Everything / Open-Shell'
                        Write-Host '                    currently: ' -NoNewline; if ($curNs) { Write-Host 'disabled' -ForegroundColor Green } else { Write-Host 'on' }
                    }
                    if (-not $gt) {
                        Write-Host '    GPU telemetry   ' -ForegroundColor White -NoNewline; Write-Host 'NVIDIA / AMD / Intel telemetry off (driver updates untouched)'
                        Write-Host '                    currently: ' -NoNewline; if ($curGt) { Write-Host 'blocked' -ForegroundColor Green } else { Write-Host 'not blocked' }
                    }
                    Write-Host ''
                    Write-Host '    Enter keeps the current answer.'
                    Move-CursorToBottom 4
                    Write-Rule
                    if (-not $ns) { $ns = Read-YesNo 'Disable Windows Search?' $curNs }
                    if (-not $gt) { $gt = Read-YesNo 'Block GPU telemetry?' $curGt }
                }
                Clear-Host
                Show-Banner -NoIntro -ExtraRows @(, @('Applying:', $t, 'Green'))
                Invoke-Apply $t @{ Keeps = $keeps; NoSearch = $ns; GpuTel = $gt }
            }
            elseif ($c -eq 'O') { Show-Options; $skipPause = $true }
            elseif ($c -eq 'S') {
                Show-Banner -NoIntro; Show-Status -FromMenu
                # Offer the fixes for what Status found: drift (re-apply) and a GDID (wipe).
                $offer = @()
                $cfgNow3 = Get-Config
                if ($script:StatusDrift -gt 0) { $offer += ('A to re-apply {0} with the same choices' -f $cfgNow3.Tier) }
                if ($script:StatusGdid) { $offer += 'W to wipe the GDID' }
                if ($offer.Count) {
                    $skipPause = $true
                    Move-CursorToBottom 3
                    Write-Rule
                    $pick = (Read-Host ('  Press ' + ($offer -join ', ') + ', or Enter to return to the menu')).Trim().ToUpper()
                    if ($pick -eq 'A' -and $script:StatusDrift -gt 0) {
                        Clear-Host
                        Show-Banner -NoIntro -ExtraRows @(, @('Applying:', $cfgNow3.Tier, 'Green'))
                        $skipPause = $false
                        Invoke-Reapply
                    }
                    elseif ($pick -eq 'W' -and $script:StatusGdid) {
                        Clear-Host
                        Show-Banner -NoIntro
                        $skipPause = $false
                        Invoke-Wipe
                    }
                }
            }
            elseif ($c -eq 'G') { Show-Banner -NoIntro; Invoke-TempUnlock $true }
            elseif ($c -eq 'L') { Show-Banner -NoIntro; Invoke-TempUnlock $false }
            elseif ($c -eq 'R') { Show-Banner -NoIntro; Invoke-RemoveEdge }
            elseif ($c -eq 'W') { Show-Banner -NoIntro; Invoke-Wipe }
            elseif ($c -eq 'U') { Show-Banner -NoIntro; Invoke-Rollback }
        }
        catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red }
        if (-not $skipPause) {
            Move-CursorToBottom 3
            Write-Rule
            [void](Read-Host '  Press Enter to return to the menu')
        }
    }
}
