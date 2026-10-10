# Telemetry & GDID Blocker - SystemTasks.ps1
# GDID report and wipe, Edge and Cortana removal, winget telemetry, search replacements.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

# ---------------------------------------------------------------------------
# GDID state (read and wipe)
# ---------------------------------------------------------------------------
function Get-InteractiveUser {
    $name = (Get-CimInstance Win32_ComputerSystem).UserName
    if (-not $name) { return $null }
    $sid = (New-Object Security.Principal.NTAccount $name).Translate([Security.Principal.SecurityIdentifier]).Value
    return @{ Name = $name; Sid = $sid }
}

function Get-GdidReport {
    param([string]$UserSid)
    $hives = [ordered]@{ 'SYSTEM' = 'S-1-5-18'; '.DEFAULT' = '.DEFAULT' }
    if ($UserSid) { $hives['user'] = $UserSid }
    $out = [ordered]@{}
    foreach ($label in $hives.Keys) {
        $p = "Registry::HKEY_USERS\$($hives[$label])\Software\Microsoft\IdentityCRL\ExtendedProperties"
        try {
            $v = (Get-ItemProperty -LiteralPath $p -Name LID -ErrorAction Stop).LID
            try { $out[$label] = 'g:{0}  (LID {1})' -f [Convert]::ToUInt64([string]$v, 16), $v }
            catch { $out[$label] = "LID $v" }
        }
        catch [System.Security.SecurityException] { $out[$label] = 'unreadable (access denied)' }
        catch { $out[$label] = 'none' }
    }
    return $out
}

function Invoke-RemoveEdgeSystem {
    param([switch]$FromEnforce)
    $root = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application'
    $marker = Join-Path $InstallDir 'edge-attempt.txt'
    $setup = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+(\.\d+){3}$' } |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName 'Installer\setup.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $setup) {
        if (-not $FromEnforce) { Write-RunLog '  Edge installer not found; Edge may already be removed.' }
        return
    }
    $ver = Split-Path (Split-Path (Split-Path $setup -Parent) -Parent) -Leaf
    if ($FromEnforce -and (Test-Path -LiteralPath $marker) -and ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $ver)) {
        return   # this Edge version already refused to uninstall; don't retry every boot
    }
    # msedge = the Edge browser only. WebView2 runs as msedgewebview2 and is never touched.
    if (Get-Process -Name msedge -ErrorAction SilentlyContinue) {
        if ($script:AllowStop) {
            Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        else {
            Write-RunLog '  Edge is open, so it was not removed. Close every Edge window (and Edge in the tray),'
            Write-RunLog '  then run Remove Edge or Apply again (with a tier applied, it is also removed at startup).'
            return
        }
    }
    Write-RunLog "  running $setup --uninstall --system-level --force-uninstall"
    $p = Start-Process -FilePath $setup -ArgumentList '--uninstall', '--system-level', '--verbose-logging', '--force-uninstall' -Wait -PassThru
    Start-Sleep -Seconds 3
    if (Test-Path -LiteralPath (Join-Path $root 'msedge.exe')) {
        Write-RunLog ("  Edge is still installed (setup exit code {0}). Outside the EEA Microsoft blocks this uninstall on current builds." -f $p.ExitCode)
        Write-RunLog '  Community option (keeps WebView2, CC0): github.com/ShadowWhisperer/Remove-MS-Edge, "Edge only". Review before running.'
        Set-Content -LiteralPath $marker -Value $ver -Encoding ASCII
    }
    else {
        Write-RunLog '  Edge removed. WebView2 untouched.'
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    }
}

function Remove-CortanaApp {
    # Cortana app (Windows 10 2004+, Windows 11 before 23H2). LTSC never had it. Runs as SYSTEM
    # in Windows PowerShell 5.1. Not reinstalled by Roll back (it is in the Microsoft Store).
    $name = 'Microsoft.549981C3F5F10'
    $pkgs = @(Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue)
    $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $name })
    if (-not $pkgs.Count -and -not $prov.Count) { return }
    if ((Get-Process -Name Cortana -ErrorAction SilentlyContinue) -and -not $script:AllowStop) {
        $script:PendingRestart += 'Cortana (removed at next startup)'
        return
    }
    foreach ($p in $pkgs) {
        try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; Write-RunLog "  removed  $($p.PackageFullName)" }
        catch { Write-RunLog "  FAILED   Cortana app: $($_.Exception.Message)" }
    }
    foreach ($p in $prov) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null; Write-RunLog "  removed  provisioned $($p.PackageName)" }
        catch { Write-RunLog "  FAILED   Cortana provisioned package: $($_.Exception.Message)" }
    }
}

function Sync-WingetTelemetry {
    # winget's own telemetry lives in each user's settings.json, not in policy. Turning it off
    # does not change how winget installs or updates. Original file kept as *.gdid-backup;
    # Roll back puts it back (or removes a file this script created).
    param([switch]$Off)
    $rel = 'AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState'
    foreach ($pk in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue)) {
        if ($pk.PSChildName -notmatch '^S-1-5-21-') { continue }
        $prof = (Get-ItemProperty -LiteralPath $pk.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $prof) { continue }
        $dir = Join-Path $prof $rel
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $f = Join-Path $dir 'settings.json'
        $bak = "$f.gdid-backup"; $made = "$f.gdid-created"
        if (-not $Off) {
            if (Test-Path -LiteralPath $bak) { Copy-Item -LiteralPath $bak -Destination $f -Force; Remove-Item -LiteralPath $bak -Force; Write-RunLog "  restored $f" }
            elseif (Test-Path -LiteralPath $made) { Remove-Item -LiteralPath $f, $made -Force -ErrorAction SilentlyContinue; Write-RunLog "  removed  $f" }
            continue
        }
        $obj = $null
        if (Test-Path -LiteralPath $f) {
            $raw = [IO.File]::ReadAllText($f)
            # settings.json allows // comment lines; Windows PowerShell 5.1 cannot parse them.
            $clean = (($raw -split "`r?`n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
            try { $obj = $clean | ConvertFrom-Json } catch { Write-RunLog "  SKIPPED  $f (not valid JSON)"; continue }
            if ($obj.PSObject.Properties['telemetry'] -and $obj.telemetry.PSObject.Properties['disable'] -and $obj.telemetry.disable -eq $true) { continue }
            if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $f -Destination $bak }
        }
        else {
            $obj = [pscustomobject]@{ '$schema' = 'https://aka.ms/winget-settings.schema.json' }
            Set-Content -LiteralPath $made -Value 'created by Telemetry & GDID Blocker' -Encoding ASCII
        }
        if (-not $obj.PSObject.Properties['telemetry']) { $obj | Add-Member -NotePropertyName telemetry -NotePropertyValue ([pscustomobject]@{}) }
        if ($obj.telemetry.PSObject.Properties['disable']) { $obj.telemetry.disable = $true }
        else { $obj.telemetry | Add-Member -NotePropertyName disable -NotePropertyValue $true }
        [IO.File]::WriteAllText($f, ($obj | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
        Write-RunLog "  set      winget telemetry off ($f)"
    }
}

function Request-SearchReplacements {
    # Shown after -DisableSearch. Offers winget installs; never installs without a yes.
    $ev = (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Everything\Everything.exe'))
    $os = (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Open-Shell\StartMenu.exe'))
    Write-Section 'WINDOWS SEARCH IS OFF'
    Write-Note @('Typing in the Start menu no longer searches, and File Explorer search is slow (no index). These replacements are recommended:')
    $evState = if ($ev) { 'installed' } else { 'winget install --id voidtools.Everything -e' }
    $osState = if ($os) { 'installed' } else { 'winget install --id Open-Shell.Open-Shell-Menu -e' }
    Write-Field 'Everything' ('instant file search with its own index - ' + $evState) 'White' 22 -Key
    Write-Field 'Open-Shell' ('Start menu that searches programs and settings - ' + $osState) 'White' 22 -Key
    if ($ev -and $os) { return }
    if ($Force) { return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Note @('winget not found: get them from voidtools.com and open-shell.github.io.'); return }
    $opts = @()
    if (-not $ev) { $opts += 'E = Everything' }
    if (-not $os) { $opts += 'O = Open-Shell' }
    if (-not $ev -and -not $os) { $opts += 'B = both' }
    $a = (Read-Host ("  Install now? {0}, Enter = no" -f ($opts -join ', '))).Trim().ToUpper()
    $ids = @()
    if ($a -in 'E', 'B' -and -not $ev) { $ids += 'voidtools.Everything' }
    if ($a -in 'O', 'B' -and -not $os) { $ids += 'Open-Shell.Open-Shell-Menu' }
    foreach ($id in $ids) { & winget install --id $id -e --source winget }
}

function Invoke-WipeSystem {
    # The services holding GDID state are stopped only if the user approved stopping. If any
    # are still running, they are set to Disabled and the wipe finishes after the next Windows restart (startup
    # task, or run Wipe again); their original start types are then restored.
    $r = Read-JsonFile $WipePath
    $userSid = if ($r) { [string]$r.Sid } else { '' }
    Write-RunLog "Wiping GDID state (user SID: $userSid)"

    $svcNames = @('wlidsvc', 'TokenBroker', 'CDPSvc', 'CDPUserSvc') + @(Get-Service -Name 'CDPUserSvc_*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $running = @($svcNames | Where-Object { $s = Get-Service -Name $_ -ErrorAction SilentlyContinue; $s -and $s.Status -ne 'Stopped' })
    $wasRunning = @()
    if ($running.Count -and $script:AllowStop) {
        foreach ($n in $running) { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue }
        $wasRunning = $running
        $running = @()
    }
    if ($running.Count) {
        $starts = @{}
        if ($r -and $r.PSObject.Properties['Starts'] -and $r.Starts) { foreach ($pp in $r.Starts.PSObject.Properties) { $starts[$pp.Name] = [int]$pp.Value } }
        foreach ($n in $svcNames) {
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
            if (-not (Test-Path -LiteralPath $k)) { continue }
            if (-not $starts.ContainsKey($n)) { $starts[$n] = [int](Get-ItemProperty -LiteralPath $k -Name Start).Start }
            Set-ItemProperty -LiteralPath $k -Name Start -Value 4 -Type DWord
        }
        Write-JsonFile $WipePath @{ Sid = $userSid; Pending = $true; Starts = $starts }
        Write-RunLog ("  DEFERRED: {0} running (not approved to stop). Set to Disabled until the wipe" -f ($running -join ', '))
        Write-RunLog '  completes. Restart Windows to finish.'
        return
    }

    $hives = @('S-1-5-18', '.DEFAULT')
    if ($userSid) { $hives += $userSid }
    foreach ($h in $hives) {
        $base = "Registry::HKEY_USERS\$h\Software\Microsoft\IdentityCRL"
        if (-not (Test-Path -LiteralPath $base)) { continue }
        try { Remove-ItemProperty -LiteralPath "$base\ExtendedProperties" -Name LID -ErrorAction Stop; Write-RunLog "  cleared  $h ExtendedProperties\LID" } catch { }
        foreach ($sub in 'Immersive\production\Property', 'DeviceIdentities\production') {
            if (Test-Path -LiteralPath "$base\$sub") {
                try { Remove-Item -LiteralPath "$base\$sub" -Recurse -Force; Write-RunLog "  removed  $h $sub" }
                catch { Write-RunLog "  FAILED   $h $sub : $($_.Exception.Message)" }
            }
        }
        $tok = "$base\Immersive\production\Token"
        if (Test-Path -LiteralPath $tok) {
            foreach ($k in @(Get-ChildItem -LiteralPath $tok)) {
                foreach ($v in 'DeviceId', 'DeviceTicket') {
                    try { Remove-ItemProperty -LiteralPath $k.PSPath -Name $v -ErrorAction Stop; Write-RunLog "  cleared  $h Token\$($k.PSChildName)\$v" } catch { }
                }
            }
        }
    }
    # Telemetry's fallback device ID (SQM machine ID); Windows generates a new one.
    try { Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\SQMClient' -Name MachineId -ErrorAction Stop; Write-RunLog '  cleared  SQMClient\MachineId' } catch { }
    $neg = 'HKLM:\SOFTWARE\Microsoft\IdentityCRL\NegativeCache'
    if (Test-Path -LiteralPath $neg) {
        Get-ChildItem -LiteralPath $neg | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-RunLog '  cleared  HKLM IdentityCRL\NegativeCache'
    }

    if ($userSid) {
        $prof = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSid" -ErrorAction SilentlyContinue).ProfileImagePath
        if ($prof) {
            foreach ($rel in 'AppData\Local\Microsoft\TokenBroker\Cache', 'AppData\Local\ConnectedDevicesPlatform') {
                $dir = Join-Path $prof $rel
                if (-not (Test-Path -LiteralPath $dir)) { continue }
                $reparse = @(Get-ChildItem -LiteralPath $dir -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
                $isLink = (((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
                if ($isLink -or ($reparse.Count -gt 0)) {
                    Write-RunLog "  SKIPPED  $dir (contains a reparse point)"
                    continue
                }
                Get-ChildItem -LiteralPath $dir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                Write-RunLog "  emptied  $dir"
            }
        }
    }

    Remove-DeviceCredentials
    # Finish a deferred wipe: restore original start types and start the automatic ones.
    if ($r -and $r.PSObject.Properties['Starts'] -and $r.Starts) {
        foreach ($pp in $r.Starts.PSObject.Properties) {
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$($pp.Name)"
            if (-not (Test-Path -LiteralPath $k)) { continue }
            Set-ItemProperty -LiteralPath $k -Name Start -Value ([int]$pp.Value) -Type DWord
            if ([int]$pp.Value -eq 2) { Start-Service -Name $pp.Name -ErrorAction SilentlyContinue }
        }
        Write-RunLog '  restored service start types after deferred wipe'
    }
    foreach ($n in $wasRunning) { Start-Service -Name $n -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $WipePath -Force -ErrorAction SilentlyContinue
}

function Remove-DeviceCredentials {
    # Deletes WindowsLive didlogical / SSO_POP_Device entries visible to the current context.
    $targets = & cmdkey.exe /list 2>$null | ForEach-Object {
        if ($_ -match '^\s*Target:\s*(.+?)\s*$' -and $Matches[1] -match 'didlogical|SSO_POP_Device') { $Matches[1] }
    }
    foreach ($t in @($targets)) {
        & cmdkey.exe "/delete:$t" | Out-Null
        Write-RunLog "  deleted  credential $t"
    }
}
