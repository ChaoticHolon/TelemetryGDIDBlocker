# Telemetry & GDID Blocker - FirewallHosts.ps1
# Firewall rules and the hosts block (rebuilt in full on every run).
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

# ---------------------------------------------------------------------------
# Firewall and hosts (owned state: fully rebuilt on every run)
# ---------------------------------------------------------------------------
function Sync-Firewall {
    param($Desired)
    $want = @{}
    foreach ($i in $Desired) {
        if ($i.Kind -eq 'FwService' -or $i.Kind -eq 'FwProgram') { $want[(Get-FwRuleName $i)] = $i }
    }
    foreach ($r in @(Get-NetFirewallRule -Group $FwGroup -ErrorAction SilentlyContinue)) {
        if (-not $want.ContainsKey($r.DisplayName)) {
            Remove-NetFirewallRule -InputObject $r
            Write-RunLog "  removed  firewall rule $($r.DisplayName)"
        }
    }
    foreach ($name in $want.Keys) {
        $i = $want[$name]
        $existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
        if ($existing) {
            if ($existing.Enabled -ne 'True') { Enable-NetFirewallRule -DisplayName $name }
            continue
        }
        try {
            if ($i.Kind -eq 'FwService') {
                New-NetFirewallRule -DisplayName $name -Group $FwGroup -Direction Outbound -Action Block -Profile Any `
                    -Program '%SystemRoot%\System32\svchost.exe' -Service $i.Service | Out-Null
            }
            else {
                New-NetFirewallRule -DisplayName $name -Group $FwGroup -Direction Outbound -Action Block -Profile Any `
                    -Program $i.Program | Out-Null
            }
            Write-RunLog "  added    firewall rule $name"
        }
        catch { Write-RunLog "  FAILED   firewall rule $name : $($_.Exception.Message)" }
    }
}

function Get-HostsText {
    if (-not (Test-Path -LiteralPath $HostsPath)) { return '' }
    return [IO.File]::ReadAllText($HostsPath)
}

function Get-HostsBlock {
    $t = Get-HostsText
    $m = [regex]::Match($t, '(?s)' + [regex]::Escape($MarkBegin) + '.*?' + [regex]::Escape($MarkEnd))
    if ($m.Success) { return $m.Value }
    return $null
}

function Sync-Hosts {
    param($Desired)
    $sections = @($Desired | Where-Object { $_.Kind -eq 'Hosts' } | ForEach-Object { $_.Section })
    $text = Get-HostsText
    if (-not (Test-Path -LiteralPath $HostsBackup) -and $text) {
        [IO.File]::WriteAllText($HostsBackup, $text, (New-Object Text.UTF8Encoding $false))
    }
    $pattern = '(?s)\r?\n?' + [regex]::Escape($MarkBegin) + '.*?' + [regex]::Escape($MarkEnd) + '\r?\n?'
    $clean = [regex]::Replace($text, $pattern, "`r`n")
    $clean = $clean.TrimEnd("`r", "`n")

    $sb = New-Object Text.StringBuilder
    if ($sections.Count -gt 0) {
        [void]$sb.Append("`r`n`r`n$MarkBegin`r`n")
        [void]$sb.Append("# login.live.com and account.live.com are listed only when personal Microsoft accounts are blocked.`r`n")
        foreach ($key in $HostsSections.Keys) {
            if ($sections -notcontains $key) { continue }
            $s = $HostsSections[$key]
            [void]$sb.Append("# --- $($s.Title) ---`r`n")
            foreach ($n in $s.Names) { [void]$sb.Append("0.0.0.0 $n`r`n:: $n`r`n") }
        }
        [void]$sb.Append("$MarkEnd`r`n")
    }
    else { [void]$sb.Append("`r`n") }
    $new = $clean + $sb.ToString()
    if ($new -ne $text) {
        $f = Get-Item -LiteralPath $HostsPath -ErrorAction SilentlyContinue
        if ($f -and $f.IsReadOnly) { $f.IsReadOnly = $false }
        [IO.File]::WriteAllText($HostsPath, $new, (New-Object Text.UTF8Encoding $false))
        & ipconfig.exe /flushdns | Out-Null
        Write-RunLog ("  hosts    rewritten ({0} sections)" -f $sections.Count)
    }
    else { Write-RunLog '  hosts    unchanged' }
}
