# Telemetry & GDID Blocker - Config.ps1
# config.json / state.json, and working out which catalog items apply.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param([string]$Path, $Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 8
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding $false))
}

function Get-Config {
    $c = Read-JsonFile $ConfigPath
    if ($null -eq $c) { return $null }
    $keeps = @()
    if ($c.PSObject.Properties['Keeps']) { $keeps = @($c.Keeps | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
    if ([string]$c.Tier -eq 'Gaming' -and $keeps -notcontains 'Gaming') { $keeps += 'Gaming' }
    $tierName = [string]$c.Tier
    $unlocked = $false
    if ($c.PSObject.Properties['Unlocked']) { $unlocked = [bool]$c.Unlocked }
    $cfg = @{ Tier = $tierName; Keeps = $keeps; Unlocked = $unlocked }
    foreach ($f in @('NoEdge', 'NoSearch', 'GpuTel')) {
        $cfg[$f] = $false
        if ($c.PSObject.Properties[$f]) { $cfg[$f] = [bool]$c.$f }
    }
    return $cfg
}

function Get-State {
    # Returns hashtable Id -> @{ Item = <def>; Orig = <original value record> }
    $h = @{}
    $s = Read-JsonFile $StatePath
    if ($null -ne $s) {
        foreach ($e in @($s)) { $h[[string]$e.Id] = @{ Item = $e.Item; Orig = $e.Orig } }
    }
    return $h
}

function Save-State {
    param([hashtable]$State)
    $list = foreach ($k in $State.Keys) { [pscustomobject]@{ Id = $k; Item = $State[$k].Item; Orig = $State[$k].Orig } }
    Write-JsonFile $StatePath @($list)
}

function Test-AccountsBlocked {
    param([hashtable]$Config)
    if ($null -eq $Config -or -not $Config.Tier) { return $false }
    return (($Config.Tier -in 'Maximum', 'Stripped') -and ($Config.Keeps -notcontains 'Accounts'))
}

function Get-AccountDependents {
    # Things on this PC that sign in with a PERSONAL Microsoft account. Best-effort detection.
    $found = [ordered]@{}
    $msa = @(Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -and [string]$_.PrincipalSource -eq 'MicrosoftAccount' })
    if ($msa.Count) { $found['WindowsLogon'] = 'Windows sign-in uses a Microsoft account: ' + (($msa | ForEach-Object { $_.Name }) -join ', ') }
    foreach ($sid in Get-LoadedUserSids) {
        $base = "Registry::HKEY_USERS\$sid\Software\Microsoft"
        foreach ($id in @(Get-ChildItem -LiteralPath "$base\Office\16.0\Common\Identity\Identities" -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $id.PSPath -ErrorAction SilentlyContinue
            if ($p -and $p.PSObject.Properties['ProviderId'] -and ([string]$p.ProviderId -match 'Live')) {
                $found['Office'] = 'Office is signed in with a personal Microsoft account'
            }
        }
        if (Test-Path -LiteralPath "$base\OneDrive\Accounts\Personal") { $found['OneDrive'] = 'OneDrive is signed in with a personal Microsoft account' }
    }
    if (Test-Path -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe')) {
        $found['VisualStudio'] = 'Visual Studio is installed'
    }
    $code = @((Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe')) + @(Get-ChildItem -Path 'C:\Users\*\AppData\Local\Programs\Microsoft VS Code\Code.exe' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    if (@($code | Where-Object { Test-Path -LiteralPath $_ }).Count) { $found['VSCode'] = 'VS Code is installed' }
    if (Test-StoreInstalled) { $found['Store'] = 'Microsoft Store is installed (installs and updates need a personal account)' }
    return $found
}

function Get-AvailableKeeps {
    # Keep switches the Keep screen offers at tier $T. Hello is deliberately not one of
    # them: it is off by default and kept only with the -KeepHello switch.
    param([string]$T)
    $a = @('Office', 'DevTools', 'Voice', 'OneDrive', 'EdgeSync', 'Edge', 'Location')
    if ($T -ne 'Gaming') { $a += 'Gaming' }                       # automatic in Gaming
    if ($T -ne 'Standard') { $a += 'PhoneLink' }                  # Standard leaves Phone Link on
    if ($T -in 'Maximum', 'Stripped') { $a += 'Accounts' }        # only these block accounts
    if ($T -in 'Standard', 'Gaming') { $a += 'SmartScreen' }      # no opt-out above Gaming
    return $a
}

function Get-SavedKeeps {
    # The Keep switches saved with the applied tier, split into those that carry over to tier
    # $T and those that do not exist there. Gaming's automatic keep does not carry over, and
    # neither does Hello: it needs -KeepHello on every Apply (HelloSaved says it was kept).
    param([string]$T)
    $cfg = Get-Config
    $prev = @()
    if ($cfg) { $prev = @($cfg.Keeps | Where-Object { $_ }) }
    if (($cfg -and $cfg.Tier -eq 'Gaming') -or $T -eq 'Gaming') { $prev = @($prev | Where-Object { $_ -ne 'Gaming' }) }
    $helloSaved = $prev -contains 'Hello'
    $prev = @($prev | Where-Object { $_ -ne 'Hello' })
    $avail = Get-AvailableKeeps $T
    return @{ Kept = @($prev | Where-Object { $avail -contains $_ }); Dropped = @($prev | Where-Object { $avail -notcontains $_ }); HelloSaved = $helloSaved }
}

function Test-SmartScreenOff {
    param([hashtable]$Config)
    if ($null -eq $Config -or -not $Config.Tier) { return $false }
    if ($Config.Tier -in 'Maximum', 'Stripped') { return $true }        # no opt-out
    return ($Config.Keeps -notcontains 'SmartScreen')                    # Standard, Gaming: opt-out
}

function Test-NoEdge {
    param([hashtable]$Config)
    if ($null -eq $Config -or -not $Config.Tier) { return $false }
    if ($Config.NoEdge) { return $true }
    return ($Config.Keeps -notcontains 'Edge')
}

function Get-EdgeInstalled {
    return (Test-Path -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'))
}

function Get-ExcludedTags {
    param([hashtable]$Config)
    $x = @()
    foreach ($k in $Config.Keeps) { if ($KeepTags.ContainsKey($k)) { $x += $KeepTags[$k] } }
    # Temp Unlock works at every tier: lift everything Gaming lifts, plus the remaining telemetry blocks.
    if ($Config.Unlocked) { $x += $KeepTags['Gaming'] + @('telemetry-hosts', 'wer') }
    if (Test-MdmEnrolled) { $x += 'mdm' }
    return $x
}

function Get-DesiredItems {
    param([hashtable]$Config)
    $result = New-Object System.Collections.ArrayList
    if ($null -eq $Config -or -not $Config.Tier) { return ,$result }
    $rank = $TierRank[$Config.Tier]
    $smart = Test-SmartScreenOff $Config
    $excluded = Get-ExcludedTags $Config
    $telemetry = Get-TelemetryLevel $Config
    $sids = Get-LoadedUserSids
    foreach ($d in $Catalog) {
        $want = $false
        if ($d.Flag -eq 'SmartScreen') { $want = $smart }
        elseif ($d.Flag -eq 'Mint') { $want = Test-AccountsBlocked $Config }
        elseif ($d.Flag -eq 'GameOn') { $want = (($Config.Keeps -contains 'Gaming') -or $Config.Unlocked) }
        elseif ($d.Flag -eq 'NoEdge') { $want = Test-NoEdge $Config }
        elseif ($d.Flag -eq 'NoSearch') { $want = [bool]($Config -and $Config.NoSearch) }
        elseif ($d.Flag -eq 'GpuTel') { $want = [bool]($Config -and $Config.GpuTel) }
        elseif ($d.Flag) { $want = [bool]$Config[$d.Flag] }
        else { $want = ($TierRank[$d.Min] -le $rank) }
        if (-not $want) { continue }
        $skip = $false
        foreach ($tg in $d.Tags) { if ($excluded -contains $tg) { $skip = $true } }
        if ($skip) { continue }
        if ($d.Kind -eq 'TaskFolder') {
            foreach ($t in @(Get-ScheduledTask -TaskPath $d.Path -ErrorAction SilentlyContinue)) {
                $ti = @{ Kind = 'Task'; Path = $t.TaskPath; Name = $t.TaskName; Min = $d.Min; Flag = $d.Flag; Tags = $d.Tags }
                $ti.Id = 'Task|{0}|{1}|||' -f $ti.Path, $ti.Name
                [void]$result.Add($ti)
            }
        }
        elseif ($d.Kind -eq 'UserReg') {
            foreach ($sid in $sids) {
                $u = $d.Clone()
                $u.Kind = 'Reg'
                $u.Path = "Registry::HKEY_USERS\$sid\$($d.Path)"
                $u.Id = 'Reg|{0}|{1}||||' -f $u.Path, $u.Name
                [void]$result.Add($u)
            }
        }
        elseif ([string]$d.Value -eq '@Telemetry') {
            $c = $d.Clone()
            $c.Value = $telemetry
            [void]$result.Add($c)
        }
        else { [void]$result.Add($d) }
    }
    return ,$result
}

function Get-ItemLabel {
    param($Item)
    switch ($Item.Kind) {
        'Reg'       {
            $p = $Item.Path -replace '^HKLM:\\SOFTWARE\\', '' -replace '^HKLM:\\SYSTEM\\.*\\Environment$', 'environment' -replace '^Registry::HKEY_USERS\\([^\\]+)\\', 'user $1 '
            return 'setting {0}\{1}' -f $p, $Item.Name
        }
        'Service'   { return 'service {0}' -f $Item.Name }
        'ServiceOn' { return 'service {0} (kept running)' -f $Item.Name }
        'Task'      { return 'task    {0}{1}' -f $Item.Path, $Item.Name }
        'FwService' { return 'firewall service {0}' -f $Item.Service }
        'FwProgram' { return 'firewall program {0}' -f (Split-Path $Item.Program -Leaf) }
        'Hosts'     { return 'hosts   {0}' -f $HostsSections[$Item.Section].Title }
    }
}

function Get-FwRuleName {
    param($Item)
    if ($Item.Kind -eq 'FwService') { return "TelemetryGDIDBlocker: service $($Item.Service)" }
    return "TelemetryGDIDBlocker: program $(Split-Path $Item.Program -Leaf)"
}


function Save-Config {
    param([hashtable]$Config)
    Write-JsonFile $ConfigPath @{
        Tier = $Config.Tier
        Keeps = @($Config.Keeps); Unlocked = [bool]$Config.Unlocked; Version = $ScriptVersion
        NoEdge = [bool]$Config.NoEdge
        NoSearch = [bool]$Config.NoSearch
        GpuTel = [bool]$Config.GpuTel
    }
}
