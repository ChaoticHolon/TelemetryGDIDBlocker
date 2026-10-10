# Telemetry & GDID Blocker v1.0

Blocks Windows' **Global Device ID (GDID)** and Microsoft telemetry, in four tiers. Changes are recorded and can be rolled back.

The GDID is a server-assigned device ID. Windows gets it the first time a personal Microsoft account signs in on the PC. It is then attached to the PC's Microsoft account sign-ins and announced to Microsoft's device graph (Phone Link / Project Rome). The only way to stop one being created is to block personal Microsoft account sign-in, which the **Maximum** and **Stripped** tiers do.

## Quick start

1. Double-click **`Start.cmd`**.
2. Approve the administrator prompt.
3. Read the Windows Hello warning (see below).
4. Answer one question: **Allow this script to stop services and close programs? [y/N/a]** (Edge, OneDrive and similar).
   - **Yes:** changes take effect immediately.
   - **No:** nothing is stopped, and the script offers to restart Windows to finish.
   - **Always:** yes, and the question is not asked again. Turn it off again under **O : Options**, **A : Always stop**. The startup and sign-in tasks never stop anything either way.
5. Pick a tier from the menu. You choose anything to keep working, then are asked about the opt-in options. Both start from your current choices, so **Enter** keeps them; on the Keep screen, type letters to replace the set or `-` for none. Choices that don't exist on the new tier (such as `-KeepSmartScreen` on Maximum) are dropped with a note. Windows Hello is never carried over: it is kept only when you run with `-KeepHello`. A progress bar then shows the tier being applied, followed by a summary of what changed and anything that failed.

`Start.cmd` uses PowerShell 7 if it is installed and falls back to Windows PowerShell 5.1. Options are passed through, for example:

```
Start.cmd -Action Apply -Tier Maximum -KeepDevTools
Start.cmd -Action Status
Start.cmd -Action Apply             # re-applies the saved tier and choices
```

> **Windows Hello:** every tier turns off Windows Hello (PIN, fingerprint, face) unless you use `-KeepHello`. You will sign in with your account **password**, so make sure you know it first. A passwordless Microsoft account needs its password turned back on at account.microsoft.com/security before you apply.

## Tiers

| | Standard | Gaming | Maximum | Stripped |
|---|---|---|---|---|
| **GDID** | | | | |
| Personal Microsoft account sign-in (creates the GDID) | On | On (Xbox needs it) | **Off** (`-KeepAccounts`) | **Off** (`-KeepAccounts`) |
| Device graph / Phone Link / Resume (announces the GDID) | On | Off | Off | Off |
| **Telemetry** | | | | |
| Diagnostic data level | Security on LTSC/Enterprise/Education, Required on Home/Pro | Required, telemetry service on | Same as Standard | Same as Standard |
| Diagnostic uploads | Blocked | Main uploads blocked, game event collectors open | Blocked | Blocked |
| Telemetry tasks, boot logging, telemetry programs | Off | Off (DiagTrack boot logging on) | Off | Off |
| Error reports sent to Microsoft | Off | Off | Off | Off |
| OneSettings remote config | Mostly off | On (Forza needs it) | Off | Off |
| ECS remote config (Teams/Edge/Office) | On | Off | Off | Off |
| **Features** | | | | |
| Spotlight, tips, suggested apps | Off | Off | Off | Off |
| Widgets, web search in Start, Copilot, Recall, Windows 11 AI | Off | Off | Off | Off |
| Cortana (app removed) | Off | Off | Off | Off |
| Location and automatic time zone | Off | Off | Off | Off |
| Windows Hello, OneDrive, Edge sign-in/sync | Off | Off | Off | Off |
| Microsoft Edge (WebView2 always kept) | Removed | Removed | Removed | Removed |
| Settings sync between PCs | On | Off | Off | Off |
| Network connectivity check | GNOME + Cloudflare | GNOME + Cloudflare | GNOME + Cloudflare | GNOME + Cloudflare |
| **Security and updates** | | | | |
| SmartScreen | Off (`-KeepSmartScreen`) | Off (`-KeepSmartScreen`) | Off, no opt-out | Off, no opt-out |
| Defender cloud protection | On | Off | Off | Off |
| Delivery Optimization cloud | On | On (Store downloads) | Off | Off |
| Windows Update | On | On | On | Off |
| **What still works** | | | | |
| Store / Xbox / Game Pass | Store yes; some games need Gaming | Yes | No (no personal account) | No |

- **Standard:** telemetry off with as little visible breakage as possible.
- **Gaming:** Maximum's blocking, except what the Microsoft Store, Xbox and Game Pass need. Personal Microsoft account sign-in, the telemetry service at Required level, OneSettings and the game event collectors stay on. Forza Horizon 6 errors E:0-17 and E:0-23-8 are caused by those being off.
- **Maximum:** Standard, plus it blocks GDID creation, the device graph, remote configuration, Defender cloud protection, Delivery Optimization cloud and settings sync. SmartScreen is off with no opt-out.
- **Stripped:** Maximum plus Windows Update off. Only for builds that ship without Defender and with Windows Update removed or paused, such as GhostSpectre. You update these by in-place upgrade or with your build's own tools.

Pick **O : Options** in the menu (or run `Start.cmd -Action Options`) for the full list of every change and what it breaks.

## Options

### Keep switches

| Switch | Keeps working |
|---|---|
| `-KeepGaming` | Microsoft Store, Xbox, Game Pass (automatic in Gaming) |
| `-KeepOffice` | Office cloud features: Designer, Editor, online templates and icons, Teams/Office remote config, Office telemetry hosts. Office itself works either way |
| `-KeepDevTools` | Visual Studio, VS Code, Application Insights / App Center hosts. At Maximum and Stripped, also lets dev tools sign in with a personal account through the browser, without creating a GDID |
| `-KeepPhoneLink` | Phone Link, Nearby Sharing, cross-device clipboard (Gaming, Maximum and Stripped; Standard leaves them on). This **is** the GDID device graph |
| `-KeepVoice` | Voice typing, voice access, online speech recognition |
| `-KeepHello` | Windows Hello PIN / biometrics |
| `-KeepOneDrive` | OneDrive sync |
| `-KeepEdgeSync` | Edge sign-in and sync, startup boost, background mode |
| `-KeepEdge` | Microsoft Edge (otherwise uninstalled) |
| `-KeepSmartScreen` | SmartScreen (Standard and Gaming only) |
| `-KeepLocation` | Location service and automatic time zone |
| `-KeepAccounts` | Personal Microsoft accounts at Maximum and Stripped (a GDID is then created). Without it, Apply warns you and asks **Are you sure? [y/N]** before blocking accounts |

### Opt-in (any tier)

| Switch | Does |
|---|---|
| `-DisableSearch` | Turns off the Windows Search indexer and blocks the Start/taskbar search box. Offers to install [Everything](https://www.voidtools.com) (file search) and [Open-Shell](https://open-shell.github.io/Open-Shell-Menu/) (Start menu with program search) with winget |
| `-BlockGpuTelemetry` | NVIDIA telemetry service, opt-out flags and telemetry hosts; AMD User Experience Program; Intel Computing Improvement Program. Driver update, sign-in and image hosts are left open. Anything not installed is skipped |

The menu asks about both options when you pick a tier.

## Menu and actions

Every menu option also has an `-Action` for scripted use.

| Menu | Action | Does |
|---|---|---|
| | *(none)* | Opens the menu |
| **1-4** | `-Action Apply -Tier <tier>` | Applies a tier with any switches. Without `-Tier`, re-applies the saved tier and choices (switches given are added) |
| **G** Temp Unlock | `-Action TempUnlock` | For games that won't sign in or sync saves: turns Xbox services and full telemetry on until Relock or the next reboot. Works at any tier; on the Gaming tier it is only needed on first launch or after a game error |
| **L** Relock | `-Action Relock` | Ends Temp Unlock now: telemetry is blocked again and Xbox services go back to how they were |
| **S** Status | `-Action Status` | Shows what is applied, any settings that have drifted, the Windows edition and the current GDID. Read-only; if anything drifted, the menu offers **A** to re-apply the same tier and choices, and if a GDID is found, **W** to wipe it |
| **O** Options | `-Action Options` | Explains every tier, switch and opt-in option, and compares the tiers |
| **R** Remove Edge | `-Action RemoveEdge` | Uninstalls Microsoft Edge without applying a tier. WebView2 is kept |
| **W** Wipe | `-Action Wipe` | Wipes the GDID and device tokens stored on this PC, plus telemetry's fallback machine ID, and shows them before and after. Only useful while personal Microsoft accounts are blocked (Maximum or Stripped without `-KeepAccounts`): otherwise Windows creates a new GDID the next time a personal account signs in |
| **U** Roll back | `-Action Rollback` | Restores the system from backups to its original state (does not reinstall apps). Asks **Are you sure? [y/N]**, then restores every recorded setting and removes the hosts block, firewall rules, scheduled tasks and the install folder. The `Logs` folder is kept |
| **Q** Quit | | Exits |

For unattended runs:
- **`-StopNow`** approves stopping services and closing programs in advance.
- **`-Force`** skips the domain-joined and Defender checks, the **Are you sure? [y/N]** confirmations and the search-replacement offer. On its own it never stops anything; add `-StopNow` if it should.

## How it works

- Changes are made by a SYSTEM scheduled task, so protected services and tasks can be changed.
- Two SYSTEM tasks re-apply your tier at startup and at each sign-in, so feature updates and Defender reverts are corrected automatically. These tasks never stop services or close programs.
- The script installs a copy of itself to `C:\ProgramData\TelemetryGDIDBlocker`, and keeps its settings (`config.json`) and the original values (`state.json`) there. That folder is locked so only SYSTEM and Administrators can change it, because the SYSTEM tasks run the script from there.
- **Logs:** each run is saved to `C:\ProgramData\TelemetryGDIDBlocker\Logs\<date_time>-<action>.log`, and the startup task saves a `Startup` log. Log names match the actions: `Apply`, `GameUnlock` (Temp Unlock and Relock), `RemoveEdge`, `Wipe`, `Rollback`, `Startup`. The newest 30 are kept, and Roll back leaves them in place, along with your saved **Always** answer (`prefs.json`). The path is shown at the end of every run.
- Approving "stop services and close programs" applies only to that run. The startup and sign-in tasks never stop anything.
- Hosts entries go between `# BEGIN TelemetryGDIDBlocker` and `# END TelemetryGDIDBlocker` markers in the Windows hosts file. Firewall rules are in the `TelemetryGDIDBlocker` group.

### Console window

The script sets the window to 110×52 so the menu fits without scrolling, and turns off QuickEdit while it runs (clicking in the window would otherwise pause it, shown as "Select" in the title bar). QuickEdit is turned back on when the script exits. Text wraps to the window width if you resize it.

### Network connectivity check

Windows checks for internet access by contacting Microsoft (`msftconnecttest.com`, `msftncsi.com`). Turning that check off makes Windows report "No Internet", and apps such as the Store act offline. Instead, every tier points the check at:

- **Web check:** GNOME's NetworkManager check (`nmcheck.gnome.org`)
- **DNS check:** Cloudflare (`one.one.one.one`)

The network icon, apps' online checks and captive-portal sign-in pages keep working, and Microsoft's check servers are blocked.

## Never touched

- Local crash dumps
- Windows activation
- Time sync
- winget (only its own telemetry is turned off)
- Root-certificate updates
- WebView2
- Work/school (Entra ID) accounts
- Defender's local scanning and definition updates (except Stripped, where definition updates are blocked)

## Not undone by Roll back

- **Microsoft Edge:** reinstall it from microsoft.com/edge.
- **Cortana:** reinstall it from the Microsoft Store.
- **Windows Hello:** if your PIN or biometrics stop working, set them up again in Settings > Accounts > Sign-in options.
- **Original values:** Roll back restores whatever the PC had before the first Apply. If another tool had already changed something, you get that tool's value back, not the Windows default.

## Requirements and support

- **Administrator rights.** Windows PowerShell 5.1 or PowerShell 7+ (7 is preferred).
- **Supported:**
  - Windows 10 Enterprise LTSC 2019 / 2021 and IoT Enterprise LTSC
  - Supported Windows 11 releases (Home/Pro 25H2 or later, Enterprise/Education 24H2 or later, LTSC 2024)
- **Out-of-support Windows** (all other Windows 10, older Windows 11 releases): shows an "insecure and unsupported" warning, then applies as normal. Problems there will not be fixed.
- **GhostSpectre and other modified builds:** flagged as modified, by name where the build leaves a marker, and by any core components it removed (Defender, Windows Security, Windows Update, Update Medic, the servicing stack, the Store outside LTSC). They are flagged because they change Windows in ways that can make some settings already changed, missing or behave differently. Applied as normal; whether the build counts as supported follows its Windows version, the same as stock Windows.
- **Windows Insider builds:** not supported. The script applies as normal and Insider flights stop.
- **Domain-joined PCs:** refused without `-Force`, because Group Policy may fight these settings.
- **Defender Tamper Protection:** may ignore the Defender cloud policy. The hosts block stops the cloud lookups either way.

## Files

```
Start.cmd                        Launcher: double-click this
hosts.txt                        Stand-alone hosts list, tagged by tier (not used by the script)
.gitattributes                   Keeps Windows line endings for the scripts in git
LICENSE                          GNU GPL v3.0
Scripts\
  TelemetryGDIDBlocker.ps1       The script: options, settings and start-up
  PSScriptAnalyzerSettings.psd1  Lint settings (Invoke-ScriptAnalyzer -Settings ...)
  Lib\                           Components, loaded by the script (not run on their own)
    Tiers.ps1                    Tier descriptions and what each Keep switch exempts
    HostsData.ps1                Hosts entries applied by each tier
    Catalog.ps1                  Every registry, service, task and firewall change, by tier
    Environment.ps1              Windows edition, build and modified-build detection
    Console.ps1                  Window, banner, sections, progress and logging
    Config.ps1                   Saved settings, original values, which changes apply
    Items.ps1                    Applies, restores and checks each change
    FirewallHosts.ps1            Firewall rules and the hosts block
    Enforce.ps1                  Applies a tier (runs as SYSTEM)
    SystemTasks.ps1              GDID wipe, Edge and Cortana removal, winget, search
    Runner.ps1                   Install folder, scheduled tasks, run logs, running as SYSTEM
    Views.ps1                    Options, tier comparison and Status screens
    Actions.ps1                  Apply, Remove Edge, Temp Unlock / Relock, Roll back, Wipe
    Menu.ps1                     Main menu
```

Keep the `Lib` folder next to the script. The script installs itself and `Lib` to `C:\ProgramData\TelemetryGDIDBlocker`, replacing the installed `Lib` folder in full each time, and the SYSTEM tasks run that copy.

### Using hosts.txt on its own

`hosts.txt` is a stand-alone hosts list for people who only want the network block, or who want to use it on a DNS blocker. Each section is tagged with the tier it belongs to. Sections that break something are commented out, with an explanation of what they break.

To use it, append the sections you want to `C:\Windows\System32\drivers\etc\hosts` as administrator, then run `ipconfig /flushdns`. The script applies the same entries itself, so you don't need this file if you use the script.

Apps that use their own encrypted DNS (DNS-over-HTTPS) bypass the hosts file. Windows' own components do not.

## Disclaimer

This changes system settings, services, scheduled tasks, the firewall and the hosts file. It is provided as-is, with no warranty. Read **O : Options** in the menu before applying, and keep a backup.

## License

Copyright (C) 2026 ChaoticHolon & contributors. Licensed under the [GNU General Public License v3.0](LICENSE) or (at your option) any later version. You can use, modify and share it; anything you distribute that is based on it must be released under the same license, with its source.
