# Telemetry & GDID Blocker - Items.ps1
# Read, apply, restore and test one catalog item of each kind.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

# ---------------------------------------------------------------------------
# Per-kind read / apply / restore / test
# ---------------------------------------------------------------------------
function Get-Original {
    param($Item)
    switch ($Item.Kind) {
        'Reg' {
            $o = @{ Exists = $false; Value = $null; Type = $null }
            if (Test-Path -LiteralPath $Item.Path) {
                $key = Get-Item -LiteralPath $Item.Path
                if ($key.GetValueNames() -contains $Item.Name) {
                    $o.Exists = $true
                    $o.Value  = $key.GetValue($Item.Name, $null, 'DoNotExpandEnvironmentNames')
                    $o.Type   = $key.GetValueKind($Item.Name).ToString()
                }
            }
            return $o
        }
        { $_ -in 'Service', 'ServiceOn' } {
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$($Item.Name)"
            if (-not (Test-Path -LiteralPath $k)) { return @{ Missing = $true } }
            return @{ Missing = $false; Start = [int](Get-ItemProperty -LiteralPath $k -Name Start).Start }
        }
        'Task' {
            $t = Get-ScheduledTask -TaskPath $Item.Path -TaskName $Item.Name -ErrorAction SilentlyContinue
            if ($null -eq $t) { return @{ Missing = $true } }
            return @{ Missing = $false; Enabled = ($t.State -ne 'Disabled') }
        }
        default { return @{} }
    }
}

function Set-ItemApplied {
    param($Item)
    switch ($Item.Kind) {
        'Reg' {
            if (-not (Test-Path -LiteralPath $Item.Path)) {
                if ($Item.OnlyIfExists) { return 'not present' }
                New-Item -Path $Item.Path -Force | Out-Null
            }
            New-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -Value $Item.Value -PropertyType $Item.Type -Force | Out-Null
            return 'set'
        }
        'Service' {
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$($Item.Name)"
            if (-not (Test-Path -LiteralPath $k)) { return 'not present' }
            Set-ItemProperty -LiteralPath $k -Name Start -Value 4 -Type DWord
            # Running services are only stopped when the user approved it for this run;
            # otherwise (and always in the startup/sign-in tasks) they stop at the next restart.
            $live = @(Get-Service -Name $Item.Name, "$($Item.Name)_*" -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Stopped' })
            if ($live.Count) {
                if ($script:AllowStop) {
                    foreach ($svc in $live) { Stop-Service -InputObject $svc -Force -ErrorAction SilentlyContinue }
                    return 'disabled + stopped'
                }
                $script:PendingRestart += $Item.Name
                return 'disabled (still running until restart)'
            }
            return 'disabled'
        }
        'ServiceOn' {
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$($Item.Name)"
            if (-not (Test-Path -LiteralPath $k)) { return 'not present' }
            $target = 2
            if ($Item.Start) { $target = [int]$Item.Start }
            if ([int](Get-ItemProperty -LiteralPath $k -Name Start).Start -eq 4) { Set-ItemProperty -LiteralPath $k -Name Start -Value $target -Type DWord }
            Start-Service -Name $Item.Name -ErrorAction SilentlyContinue
            return 'enabled'
        }
        'Task' {
            $t = Get-ScheduledTask -TaskPath $Item.Path -TaskName $Item.Name -ErrorAction SilentlyContinue
            if ($null -eq $t) { return 'not present' }
            if ($t.State -ne 'Disabled') { Disable-ScheduledTask -InputObject $t | Out-Null }
            return 'disabled'
        }
        default { return 'ok' }
    }
}

function Restore-Item {
    param($Item, $Orig)
    switch ($Item.Kind) {
        'Reg' {
            if (-not (Test-HiveLoaded $Item.Path)) { throw 'user profile not loaded' }
            if ($Orig.Exists) {
                if (-not (Test-Path -LiteralPath $Item.Path)) { New-Item -Path $Item.Path -Force | Out-Null }
                New-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -Value $Orig.Value -PropertyType $Orig.Type -Force | Out-Null
            }
            elseif (Test-Path -LiteralPath $Item.Path) {
                Remove-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -ErrorAction SilentlyContinue
            }
        }
        { $_ -in 'Service', 'ServiceOn' } {
            if ($Orig.Missing) { return }
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$($Item.Name)"
            if (-not (Test-Path -LiteralPath $k)) { return }
            Set-ItemProperty -LiteralPath $k -Name Start -Value ([int]$Orig.Start) -Type DWord
            if ([int]$Orig.Start -le 2) { Start-Service -Name $Item.Name -ErrorAction SilentlyContinue }
            elseif ((Get-Service -Name $Item.Name -ErrorAction SilentlyContinue).Status -eq 'Running') {
                if ($script:AllowStop) { Stop-Service -Name $Item.Name -Force -ErrorAction SilentlyContinue }
                else { $script:PendingRestart += $Item.Name }
            }
        }
        'Task' {
            if ($Orig.Missing -or -not $Orig.Enabled) { return }
            $t = Get-ScheduledTask -TaskPath $Item.Path -TaskName $Item.Name -ErrorAction SilentlyContinue
            if ($t) { Enable-ScheduledTask -InputObject $t | Out-Null }
        }
    }
}

function Test-ItemApplied {
    # Returns 'ok', 'drift' or 'n/a'
    param($Item)
    switch ($Item.Kind) {
        'Reg' {
            if ($Item.OnlyIfExists -and -not (Test-Path -LiteralPath $Item.Path)) { return 'n/a' }
            $o = Get-Original $Item
            if ($o.Exists -and ([string]$o.Value -eq [string]$Item.Value)) { return 'ok' }
            return 'drift'
        }
        'Service' {
            $o = Get-Original $Item
            if ($o.Missing) { return 'n/a' }
            if ($o.Start -eq 4) { return 'ok' }
            return 'drift'
        }
        'ServiceOn' {
            $o = Get-Original $Item
            if ($o.Missing) { return 'n/a' }
            if ($o.Start -eq 4) { return 'drift' }
            if ($Item.Start -and [int]$Item.Start -gt 2) { return 'ok' }
            $s = Get-Service -Name $Item.Name -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq 'Running') { return 'ok' }
            return 'drift'
        }
        'Task' {
            $o = Get-Original $Item
            if ($o.Missing) { return 'n/a' }
            if (-not $o.Enabled) { return 'ok' }
            return 'drift'
        }
        { $_ -in 'FwService', 'FwProgram' } {
            $r = Get-NetFirewallRule -DisplayName (Get-FwRuleName $Item) -ErrorAction SilentlyContinue
            if ($r -and $r.Enabled -eq 'True') { return 'ok' }
            return 'drift'
        }
        'Hosts' {
            $block = Get-HostsBlock
            $first = $HostsSections[$Item.Section].Names[0]
            if ($block -and $block -match [regex]::Escape(" $first")) { return 'ok' }
            return 'drift'
        }
    }
}
