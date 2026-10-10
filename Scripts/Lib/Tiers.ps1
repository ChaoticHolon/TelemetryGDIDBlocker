# Telemetry & GDID Blocker - Tiers.ps1
# Tier ranks, Keep-switch tags and the tier descriptions shown in Options.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

# Gaming shares Maximum's rank; its difference is the KeepGaming exclusions.
$TierRank        = @{ Standard = 1; Gaming = 2; Maximum = 2; Stripped = 3 }
# Tags each Keep removes from the plan.
$KeepTags = @{
    Gaming    = @('telemetry-service', 'onesettings', 'store', 'game-events', 'diag-limits')
    Office    = @('office')
    DevTools  = @('dev')
    PhoneLink = @('cdp')
    Voice     = @('voice')
    Hello     = @('hello')
    OneDrive  = @('onedrive')
    EdgeSync  = @('edgesync')
    Edge      = @()
    SmartScreen = @()
    Location  = @('location')
    Accounts  = @()
}

$TierInfo = [ordered]@{
    Standard = @{
        UseCase = @(
            'For most PCs. Stops Windows telemetry while keeping what you are likely to use: the'
            'Microsoft Store, Office and personal Microsoft account sign-in keep working; some Xbox /'
            'Game Pass games need Gaming. Does NOT stop the GDID being created (that needs Maximum'
            'or Stripped).'
        )
        Base   = ''
        Adds   = @(
            'SmartScreen URL / download reputation lookups off (-KeepSmartScreen)'
            'Diagnostic data (DiagTrack) and WAP push services off; error reports never uploaded'
            '  (local crash dumps are kept)'
            'Windows Spotlight, lock-screen tips and suggested apps off (no opt-out)'
            'Widgets / News and Interests, search highlights and Start recommendations off;'
            '  Comscore and OneTrust beacons they load are hosts-blocked (no opt-out)'
            'Windows Hello PIN/biometrics, OneDrive sync and Edge sign-in/sync off (Keep switches)'
            'Microsoft Edge uninstalled, WebView2 kept, reinstall blocked (-KeepEdge)'
            'Web results and cloud content in Start search, Copilot and Recall off'
            'Cortana off and its app removed for all users (not reinstalled by Roll back)'
            'Office optional connected experiences, CEIP, feedback and surveys off (-KeepOffice);'
            '  winget telemetry off (winget itself untouched)'
            'CEIP, Compatibility Appraiser, DeviceCensus, Feedback and disk-diagnostic tasks off'
            'DiagTrack-Listener and SQMLogger ETW boot sessions off (collection stops at the source)'
            'Telemetry, error-reporting, advertising ID, activity upload, consumer "suggestions",'
            '  inking/typing personalization, online speech and Edge diagnostic-data settings'
            '.NET CLI, PowerShell, Visual Studio and Office telemetry opt-outs'
            'Telemetry executables blocked from running (IFEO): CompatTelRunner, DeviceCensus,'
            '  aitstatic, DiagTrackRunner, wsqmcons; Device Health Attestation, device metadata,'
            '  disk-health model, WMDRM, offline-maps and language-list web traffic off'
            'Census / Appraiser / SQM client flags, storage (StorPort) telemetry, experimentation,'
            '  linguistic data, typing insights, cloud search, Insider, inventory and Family Safety'
            '  monitor services, and the remaining CEIP / diagnosis / hive-upload tasks off'
            'Telemetry service upload switches, CEIP opt-in, PerfTrack, help/tips feedback, typing'
            '  data logger, error-report sending, Media Player tracking, disk-footprint task off'
            'Firewall blocks DiagTrack, CompatTelRunner, DeviceCensus, WerFault, wermgr'
            'Network connectivity check moved off Microsoft to GNOME (web) and one.one.one.one (DNS);'
            '  network icon, app online checks and captive-portal sign-in keep working'
            'Location service, location scripting, Find My Device, Maps broker and automatic time'
            '  zone service off (-KeepLocation); time sync unaffected'
            'Windows 11: Recall data providers, Notepad/Paint cloud AI, lock-screen widgets, Graph /'
            '  Office.com content in Start and File Explorer, "finish setting up" prompts off'
            'Hosts: Windows diagnostic data, game/app event collectors (mobile.events), Microsoft'
            '  connectivity check, location lookups, Office/Teams, developer telemetry,'
            '  ads/Spotlight/Clarity, SmartScreen'
        )
        Breaks = @(
            'PIN/biometric sign-in (password instead); OneDrive sync; Microsoft Edge; web results in'
            'Start search; Copilot; Feedback Hub;'
            'Spotlight images; Widgets board and lock-screen widgets; Family Safety activity reports;'
            'location for every app (Maps, Weather, Find My Device) and automatic time zone: set'
            '  it manually in Settings or with tzutil /s (-KeepLocation); Notepad/Paint AI features;'
            'SmartScreen download checks;'
            'voice typing (use -KeepVoice). Some Xbox/Game Pass games need the telemetry'
            'service to start or sync saves: use the Gaming tier or -KeepGaming.'
        )
    }
    Gaming = @{
        UseCase = @(
            'For gaming PCs that use Xbox, Game Pass or the Microsoft Store and should just work.'
            'Blocks as much as Maximum except what those need. The telemetry service runs at the'
            'Required level because some games (e.g. Forza Horizon 6) will not start or sync saves'
            'without it. Does NOT stop the GDID being created.'
        )
        Base   = 'Maximum blocking, EXCEPT these stay working:'
        Adds   = @(
            'Connected User Experiences and Telemetry (DiagTrack), Gaming Services and the Xbox'
            '  services (auth, game save, networking, accessories) enabled and started, even if a'
            '  debloat tool disabled them (Forza Horizon 6 E:0-23-8); telemetry at Required level'
            'OneSettings reachable and allowed (DisableOneSettingsDownloads=0): Gaming Services'
            '  needs it to create save folders (Forza Horizon 6 error E:0-17)'
            'LimitDiagnosticLogCollection=0; game event collectors (mobile.events) reachable'
            'Microsoft Store, Gaming Services and Game Pass downloads (DO, Windows Update plumbing)'
            'Main Windows diagnostic uploads (v10/v20/self events) stay hosts-blocked'
            'Everything else from Maximum except the personal-account block: device graph, ECS,'
            '  sync and Defender cloud off; -KeepSmartScreen still available (not at Maximum)'
            'First launch, after reinstalling, or on E:0-23-8 / 0x80600008: Temp Unlock (G),'
            '  play until online (Horizon Life) connects and saves sync, then Relock (L)'
        )
        Breaks = @(
            'Phone Link, Nearby Sharing, cross-device clipboard, settings sync; Teams/Office remote'
            'features and Designer/Editor (-KeepOffice); Mail / Calendar / People app sync;'
            'Defender cloud lookups; SmartScreen download checks (-KeepSmartScreen).'
            'Less telemetry blocked than Maximum: Required-level diagnostic data is still collected.'
        )
    }
    Maximum = @{
        UseCase = @(
            'For PCs that do not need a personal Microsoft account: local-account PCs without the'
            'Store or Xbox. With Stripped, the only tier that stops the GDID being created.'
            'Work/school (Entra ID) accounts keep working; -KeepAccounts restores personal ones.'
        )
        Base   = 'Standard, plus:'
        Adds   = @(
            'GDID device-graph registration: CDP services disabled and firewalled; DDS, CDP,'
            '  Project Rome and Activity hosts blocked'
            'Defender cloud protection (MAPS) off: no file metadata or samples sent; local'
            '  scanning and definition updates unaffected'
            'Remote configuration: OneSettings downloads off; OneSettings and ECS hosts blocked'
            '  (-KeepOffice keeps ECS for Teams/Office)'
            'Delivery Optimization set to Simple mode (no peer-to-peer) and its cloud hosts blocked'
            'Settings sync off; Windows 11 "Resume" (continue phone apps on the PC) off'
            'Office content-analysing (Designer, Editor) and online-content experiences off'
            '  (-KeepOffice)'
            'SmartScreen off with no opt-out'
            'Sync host (OneSyncSvc), diagnostic execution service and language-settings sync off'
            'Personal Microsoft account sign-in blocked (wlidsvc firewalled, "Block Microsoft'
            '  accounts" policy, login.live.com sinkholed): no GDID is created (-KeepAccounts)'
            '  Work/school accounts unaffected; -KeepDevTools allows browser sign-in for dev tools'
        )
        Breaks = @(
            'Phone Link, Nearby Sharing, cross-device clipboard, "continue on PC"; settings sync'
            'between PCs; DO peer-to-peer downloads; Xbox/Game Pass games that need telemetry'
            '(use Gaming); Xbox app and Feedback Hub; Teams/Office remote features (-KeepOffice);'
            'Mail / Calendar / People app sync; SmartScreen download checks (no opt-out);'
            'Defender cloud lookups; everything that needs a PERSONAL Microsoft account:'
            'Microsoft Store, OneDrive personal, Office/M365 personal, Xbox, Phone Link,'
            'Microsoft-account Windows sign-ins.'
        )
    }
    Stripped = @{
        UseCase = @(
            'Only for modified builds such as GhostSpectre that ship without Defender and with'
            'Windows Update removed or paused, and are updated by in-place upgrade. Maximum plus'
            'Windows Update off. Not for stock Windows.'
        )
        Base   = 'Maximum, plus (only for builds shipped WITHOUT Defender and Windows Update):'
        Adds   = @(
            'Windows Update, Update Orchestrator, WaaSMedic, Update Health, DO services disabled'
            'Update Orchestrator / Windows Update / WaaSMedic tasks disabled; update policies set'
            'SIHClient, WaaSMedicAgent, UsoClient blocked from running (IFEO); no driver search on WU'
            'Hosts: Windows Update and Defender definition servers blocked'
            'Root-certificate updates (ctldl.windowsupdate.com) and Store downloads stay open'
            'With -KeepGaming: Windows Update and DO services stay available for the Store'
        )
        Breaks = @(
            'ALL Windows Update and Defender definition updates. Update by in-place upgrade'
            '(or your build''s toolbox) instead.'
        )
    }
}
