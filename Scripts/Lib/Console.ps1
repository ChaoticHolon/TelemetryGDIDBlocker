# Telemetry & GDID Blocker - Console.ps1
# Console output: logging, banner, sections, word-wrap, progress, QuickEdit, window size.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-RunLog {
    param([string]$Message)
    $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $Message
    try { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 } catch { }
    Write-Host $Message
}

function Find-Pwsh {
    $c = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($p in @((Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'))) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Set-ConsoleSize {
    # Sizes a classic console window so the menus and tier pages fit without scrolling,
    # while keeping a tall buffer so long Apply logs can still be scrolled back.
    # Has no effect in Windows Terminal, which sizes its own windows.
    param([int]$Width = 110, [int]$Height = 52)
    try {
        $ui = $Host.UI.RawUI
        $max = $ui.MaxPhysicalWindowSize
        $w = [Math]::Min($Width, $max.Width); $h = [Math]::Min($Height, $max.Height)
        $buf = $ui.BufferSize
        $ui.BufferSize = New-Object Management.Automation.Host.Size ([Math]::Max($buf.Width, $w)), ([Math]::Max($buf.Height, 3000))
        $ui.WindowSize = New-Object Management.Automation.Host.Size $w, $h
        $ui.BufferSize = New-Object Management.Automation.Host.Size $w, $ui.BufferSize.Height
    }
    catch { }
}

function Get-WindowsLabel {
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    if (-not $cv) { return 'unknown' }
    $build = [int]$cv.CurrentBuildNumber
    $name = [string]$cv.ProductName
    if ($build -ge 22000) { $name = $name -replace '^Windows 10', 'Windows 11' }   # ProductName still says 10 on 11
    $parts = @($name)
    if ($cv.PSObject.Properties['DisplayVersion'] -and $cv.DisplayVersion) { $parts += [string]$cv.DisplayVersion }
    $parts += ('build {0}.{1}' -f $build, $cv.UBR)
    return ($parts -join ', ')
}

function Write-Section {
    param([string]$Title, [string]$Note = '')
    Write-Host ''
    Write-Host ('  ' + $Title) -ForegroundColor Cyan -NoNewline
    if ($Note) { Write-Host ('  ' + $Note) } else { Write-Host '' }
}

function Get-ConsoleWidth {
    try { return [Math]::Max(60, $Host.UI.RawUI.WindowSize.Width - 1) } catch { return 109 }
}

function Split-ToWidth {
    # Word-wraps text into lines no longer than $Width characters.
    param([string]$Text, [int]$Width)
    if ($Width -lt 20) { $Width = 20 }
    $out = New-Object System.Collections.ArrayList
    $line = ''
    foreach ($w in ($Text -split ' ')) {
        if ($line.Length -eq 0) { $line = $w }
        elseif (($line.Length + 1 + $w.Length) -le $Width) { $line += ' ' + $w }
        else { [void]$out.Add($line); $line = $w }
        while ($line.Length -gt $Width) { [void]$out.Add($line.Substring(0, $Width)); $line = $line.Substring($Width) }
    }
    if ($line.Length) { [void]$out.Add($line) }
    return ,$out
}

function Write-Field {
    # Indented "label   value" row used on the status and switches pages. Long values wrap
    # under the value column instead of running past the window edge.
    # -Key: label in yellow and value in the normal colour (switch lists).
    param([string]$Label, [string]$Value, [string]$Color = 'White', [int]$Width = 22, [switch]$Key)
    $lab = (('    {0,-' + $Width + '}') -f $Label)
    $avail = (Get-ConsoleWidth) - $lab.Length
    $parts = Split-ToWidth $Value $avail
    $pad = ' ' * $lab.Length
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $prefix = if ($i -eq 0) { $lab } else { $pad }
        if ($Key) { Write-Host $prefix -ForegroundColor Yellow -NoNewline; Write-Host $parts[$i] }
        else { Write-Host $prefix -NoNewline; Write-Host $parts[$i] -ForegroundColor $Color }
    }
}

function Hide-Cursor {
    # Progress bars move the cursor to redraw, which makes it flicker; hide it meanwhile.
    try { [Console]::CursorVisible = $false } catch { }
}

function Show-Cursor {
    try { [Console]::CursorVisible = $true } catch { }
}

function Write-InlineProgress {
    # The one progress bar used everywhere (Status checks, Apply/Wipe/Roll back, Wipe's user
    # step). A background thread does the drawing: it redraws every 80 ms, turns the spinner
    # and eases the bar toward the real count, whatever the foreground is doing. Calls only
    # hand it the latest numbers.
    #   Write-InlineProgress <done> <total> <label>   start, or update
    #   Write-InlineProgress -Keep                    fill to 100%, leave the bar, move below it
    #   Write-InlineProgress -Keep -Unfinished        leave the bar where it stopped (timed out)
    #   Write-InlineProgress -Clear                   stop and wipe the line (fills to 100% first
    #                                                 if the last update reached the total)
    param([double]$Done, [double]$Total, [string]$Label, [switch]$Clear, [switch]$Keep, [switch]$Unfinished)
    $live = $script:InlineLive
    if ($Clear -or $Keep) {
        if ($live) {
            if ($Label) { $live.State.Label = $Label }
            if ($Keep -and -not $Unfinished) { $live.State.Done = $live.State.Total }
            $live.State.Keep = $Keep -and -not $Unfinished
            $live.State.Stop = $true
            try { [void]$live.PS.EndInvoke($live.Handle) } catch { }
            $live.PS.Dispose(); $live.RS.Dispose()
            $row = $live.State.Row
            try {
                if ($Keep) { [Console]::SetCursorPosition(0, $row + 1) }
                else { [Console]::SetCursorPosition(0, $row); [Console]::Write(' ' * $live.State.Width); [Console]::SetCursorPosition(0, $row) }
            }
            catch { }
            $script:InlineLive = $null
        }
        Show-Cursor
        return
    }
    if (-not $live) {
        $width = 100
        try { $width = [Math]::Max(60, $Host.UI.RawUI.WindowSize.Width - 4) } catch { }
        $row = 0
        try { $row = [Console]::CursorTop } catch { }
        $state = [hashtable]::Synchronized(@{ Done = 0.0; Total = 1.0; Label = ''; Stop = $false; Keep = $false; Row = $row; Width = $width })
        $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
        $rs.SessionStateProxy.SetVariable('S', $state)
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript({
            $spin = '|', '/', '-', '\'
            $tick = 0; $shown = 0.0
            while ($true) {
                $stop = $S.Stop
                $fill = $stop -and ($S.Keep -or $S.Done -ge $S.Total)   # finished: animate to 100%
                $target = 0.0
                if ($S.Total -gt 0) { $target = [Math]::Min(100, $S.Done * 100.0 / $S.Total) }
                if (-not $stop -and $target -gt 99) { $target = 99 }       # 100% only once finished
                if ($fill) { $step = [Math]::Max(4, ($target - $shown) / 3) }   # quick final fill
                else { $step = [Math]::Max(0.5, ($target - $shown) / 4) }
                if ($shown -lt $target) { $shown = [Math]::Min($target, $shown + $step) }
                $p = [int][Math]::Floor($shown)
                $filled = [int][Math]::Floor($shown / 5)
                $mark = if ($p -ge 100) { ' ' } else { $spin[$tick % 4] }
                $text = ('    [{0}{1}] {2,3}% {3} {4}' -f ('#' * $filled), ('-' * (20 - $filled)), $p, $mark, $S.Label)
                if ($text.Length -gt $S.Width) { $text = $text.Substring(0, $S.Width - 3) + '...' }
                try { [Console]::SetCursorPosition(0, $S.Row); [Console]::Write($text.PadRight($S.Width)) } catch { }
                if ($stop -and (-not $fill -or $shown -ge $target)) { break }
                Start-Sleep -Milliseconds $(if ($stop) { 25 } else { 80 })
                $tick++
            }
        })
        Hide-Cursor
        $script:InlineLive = $live = @{ PS = $ps; RS = $rs; State = $state; Handle = $ps.BeginInvoke() }
    }
    $live.State.Label = $Label; $live.State.Total = $Total; $live.State.Done = $Done
}

function Read-YesNo {
    # Yes/no prompt where Enter keeps the default (shown in capitals).
    param([string]$Question, [bool]$Default)
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $a = (Read-Host "  $Question $hint").Trim()
    if ($a -eq '') { return $Default }
    return ($a -match '^(y|yes)$')
}

function Write-WarnBlock {
    # Themed warning: one "WARNING: TITLE" heading, then indented, wrapped lines.
    param([string]$Title, [string[]]$Lines, [string]$Color = 'Yellow')
    Write-Host ''
    Write-Host ('  WARNING: ' + $Title) -ForegroundColor $Color
    Write-Note $Lines
}

function Write-Note {
    # Indented note under a field; Yellow or Red for warnings. Wraps to the window width.
    param([string[]]$Lines, [string]$Color = '')
    $avail = (Get-ConsoleWidth) - 6
    foreach ($l in $Lines) {
        foreach ($part in (Split-ToWidth $l $avail)) {
            if ($Color) { Write-Host ('      ' + $part) -ForegroundColor $Color } else { Write-Host ('      ' + $part) }
        }
    }
}

function Write-Rule { Write-Host ('  ' + ('-' * 96)) -ForegroundColor DarkCyan }

function Disable-QuickEdit {
    # Clicking in a console with QuickEdit on pauses the script until a key is pressed, which
    # looks like a hang. Turn it off for this window; Restore-QuickEdit puts it back on exit.
    try {
        if (-not ('TGB.ConsoleMode' -as [type])) {
            Add-Type -Namespace TGB -Name ConsoleMode -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr h, out uint mode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr h, uint mode);
'@
        }
        $h = [TGB.ConsoleMode]::GetStdHandle(-10)
        $m = [uint32]0
        if ([TGB.ConsoleMode]::GetConsoleMode($h, [ref]$m)) {
            $script:OrigConsoleMode = $m
            [void][TGB.ConsoleMode]::SetConsoleMode($h, (($m -band (-bnot [uint32]0x40)) -bor [uint32]0x80))
        }
    }
    catch { }
}

function Restore-QuickEdit {
    try { if ($null -ne $script:OrigConsoleMode) { [void][TGB.ConsoleMode]::SetConsoleMode([TGB.ConsoleMode]::GetStdHandle(-10), $script:OrigConsoleMode) } } catch { }
    Show-Cursor
}

function Show-Banner {
    # -NoIntro skips the description (menus). -ExtraRows: @(label, value, colour) rows.
    param([switch]$NoIntro, [object[]]$ExtraRows = @())
    try { $Host.UI.RawUI.WindowTitle = "$ScriptName v$ScriptVersion" } catch { }
    $wide = $true
    try { $wide = $Host.UI.RawUI.WindowSize.Width -ge 100 } catch { }
    Write-Host ''
    if ($wide) {
        $art = @'
 _____    _               _              __        ___ ___ ___ ___    ___ _         _
|_   _|__| |___ _ __  ___| |_ _ _ _  _  / _|___   / __|   \_ _|   \  | _ ) |___  __| |_____ _ _
  | |/ -_) / -_) '  \/ -_)  _| '_| || | > _|_ _| | (_ | |) | || |) | | _ \ / _ \/ _| / / -_) '_|
  |_|\___|_\___|_|_|_\___|\__|_|  \_, | \_____|   \___|___/___|___/  |___/_\___/\__|_\_\___|_|
                                  |__/
'@ -split "`r?`n"
        foreach ($l in $art) { Write-Host ('  ' + $l) -ForegroundColor Cyan }
        $artWidth = ($art | Measure-Object -Property Length -Maximum).Maximum
        Write-Host (('  {0,' + $artWidth + '}') -f "v$ScriptVersion") -ForegroundColor White
    }
    else { Write-Host ("  {0}  v{1}" -f $ScriptName.ToUpper(), $ScriptVersion) -ForegroundColor Cyan }
    Write-Host ''
    if (-not $NoIntro) {
        Write-Host '  Blocks Windows'' Global Device ID (GDID) and Microsoft telemetry in four tiers:'
        Write-Host '  Standard, Gaming, Maximum and Stripped. Every change is recorded and can be undone'
        Write-Host '  with Roll back (Edge and Cortana are not reinstalled).'
        Write-Host ''
    }
    Write-Rule
    $v = $PSVersionTable.PSVersion
    $psv = '{0}.{1}' -f $v.Major, $v.Minor
    if ($v.Major -lt 7) { $psv += ' (Windows PowerShell)' }
    $cur = 'none applied'; $curColor = 'White'
    $cfg = $null
    try { $cfg = Get-Config } catch { }
    if ($cfg) {
        $cur = $cfg.Tier; $curColor = 'Green'
        if ($cfg.Keeps.Count) { $cur += ' (keeping ' + ($cfg.Keeps -join ', ') + ')' }
        if ($cfg.Unlocked) { $cur += '  [TEMP UNLOCK ACTIVE]'; $curColor = 'Yellow' }
    }
    $rows = @(@('Running in', "PowerShell $psv", 'White'), @('Build Detected:', (Get-WindowsLabel), 'White'), @('Current Tier:', $cur, $curColor)) + $ExtraRows
    foreach ($row in $rows) {
        Write-Host ('  ' + $row[0] + ' ') -ForegroundColor Cyan -NoNewline
        Write-Host $row[1] -ForegroundColor $row[2]
    }
    Write-Rule
}
