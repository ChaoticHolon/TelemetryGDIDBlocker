# Telemetry & GDID Blocker - Catalog.ps1
# Catalog of every change (registry, services, tasks, firewall, hosts), tagged by tier.
# Loaded by TelemetryGDIDBlocker.ps1; not run on its own.

if ($MyInvocation.InvocationName -ne '.') { throw 'This file is part of Telemetry & GDID Blocker. Run Start.cmd (or Scripts\TelemetryGDIDBlocker.ps1) instead.' }

# ---------------------------------------------------------------------------
# Catalog of changes.
#   Min  = lowest tier that applies it.
#   Flag = only when that option is active (SmartScreen, Mint), regardless of tier.
#   Tags = removed from the plan when a matching Keep is active (see $KeepTags).
#   UserReg items are written to every loaded user profile (HKEY_USERS\<SID>\...).
#   Value '@Telemetry' is resolved from the Windows edition and Gaming settings.
# ---------------------------------------------------------------------------
$Catalog = New-Object System.Collections.ArrayList

function Add-Def {
    param([string]$Min, [string]$Kind, [hashtable]$P, [string]$Flag = '')
    $P.Kind = $Kind
    $P.Min  = $Min
    $P.Flag = $Flag
    $P.Tags = @()
    if (-not $P.ContainsKey('Type')) { $P.Type = 'DWord' }
    $P.Id = '{0}|{1}|{2}|{3}|{4}|{5}' -f $Kind, $P.Path, $P.Name, $P.Service, $P.Program, $P.Section
    [void]$Catalog.Add($P)
}
function Tag { param([string[]]$Tags) $Catalog[$Catalog.Count - 1].Tags = $Tags }
function Add-Reg   { param($Min, $Path, $Name, $Value, $Type = 'DWord', $Flag = '') Add-Def $Min 'Reg' @{ Path = $Path; Name = $Name; Value = $Value; Type = $Type } $Flag }
function Add-UReg  { param($Min, $Path, $Name, $Value, $Type = 'DWord') Add-Def $Min 'UserReg' @{ Path = $Path; Name = $Name; Value = $Value; Type = $Type } }
function Add-Svc   { param($Min, $Name, $Flag = '') Add-Def $Min 'Service' @{ Name = $Name } $Flag }
function Add-Task  { param($Min, $Path, $Name, $Flag = '') Add-Def $Min 'Task' @{ Path = $Path; Name = $Name } $Flag }
function Add-TaskF { param($Min, $Path, $Flag = '') Add-Def $Min 'TaskFolder' @{ Path = $Path } $Flag }
function Add-FwSvc { param($Min, $Service, $Flag = '') Add-Def $Min 'FwService' @{ Service = $Service } $Flag }
function Add-FwExe { param($Min, $Program, $Flag = '') Add-Def $Min 'FwProgram' @{ Program = $Program } $Flag }
function Add-Hosts { param($Min, $Section, $Flag = '') Add-Def $Min 'Hosts' @{ Section = $Section } $Flag }

$P   = 'HKLM:\SOFTWARE\Policies\Microsoft'
$PW  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
$AE  = '\Microsoft\Windows\Application Experience\'
$CE  = '\Microsoft\Windows\Customer Experience Improvement Program\'
$ENV = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$CDM = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

# --- Standard: Windows diagnostic data ---------------------------------------
Add-Svc  Standard 'DiagTrack';                                   Tag 'telemetry-service'
Add-FwSvc Standard 'DiagTrack';                                  Tag 'telemetry-service'
# ETW AutoLogger sessions that feed DiagTrack / CEIP (BSI SiSyPHuS Win10 finding): stop them
# collecting at boot, independent of whether the service or network is blocked.
Add-Def Standard 'Reg' @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener'; Name = 'Start'; Value = 0; OnlyIfExists = $true };  Tag 'telemetry-service'
Add-Def Standard 'Reg' @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Diagtrack-Listener'; Name = 'Start'; Value = 0; OnlyIfExists = $true };  Tag 'telemetry-service'
Add-Def Standard 'Reg' @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\SQMLogger'; Name = 'Start'; Value = 0; OnlyIfExists = $true }
Add-Def Standard 'Reg' @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\CloudExperienceHostOobe'; Name = 'Start'; Value = 0; OnlyIfExists = $true }
Add-Svc  Standard 'dmwappushservice';                            Tag 'mdm'
Add-Reg  Standard "$PW\DataCollection" 'AllowTelemetry' '@Telemetry'
# Some games (Forza Horizon 6) check this second key too.
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' '@Telemetry'
Add-Reg  Standard "$PW\DataCollection" 'AllowDeviceNameInTelemetry' 0
Add-Reg  Standard "$PW\DataCollection" 'DoNotShowFeedbackNotifications' 1
Add-Reg  Standard "$PW\DataCollection" 'LimitDiagnosticLogCollection' 1;          Tag 'diag-limits'
Add-Reg  Standard "$PW\DataCollection" 'DisableTelemetryOptInChangeNotification' 1
Add-Reg  Standard "$PW\DataCollection" 'AllowCommercialDataPipeline' 0
Add-Reg  Standard "$PW\DataCollection" 'AllowDesktopAnalyticsProcessing' 0
Add-Reg  Standard "$PW\DataCollection" 'DisableEnterpriseAuthProxy' 1
Add-Reg  Standard "$PW\DataCollection" 'LimitEnhancedDiagnosticDataWindowsAnalytics' 1
# Telemetry executables: Image File Execution Options makes Windows run "cmd /c exit" instead,
# so they cannot run at all - this works even where the firewall is off.
$IFEO = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
foreach ($exe in 'CompatTelRunner.exe', 'DeviceCensus.exe', 'aitstatic.exe', 'DiagTrackRunner.exe', 'wsqmcons.exe') {
    Add-Reg Standard "$IFEO\$exe" 'Debugger' '%SystemRoot%\System32\cmd.exe /c exit' 'String'
}
# Device Health Attestation (TPM-backed health reports); MDM compliance uses it, so MDM keeps it.
Add-Reg  Standard "$P\DeviceHealthAttestationService" 'EnableDeviceHealthAttestationService' 0;  Tag 'mdm'
Add-Reg  Standard "$PW\Device Metadata" 'PreventDeviceMetadataFromNetwork' 1
Add-Reg  Standard "$PW\StorageHealth" 'AllowDiskHealthModelUpdates' 0
Add-Reg  Standard "$P\WMDRM" 'DisableOnline' 1
Add-Reg  Standard "$PW\Maps" 'AutoDownloadAndUpdateMapData' 0
Add-Reg  Standard "$PW\Maps" 'AllowUntriggeredNetworkTrafficOnSettingsPage' 0
Add-Reg  Standard "$PW\AppPrivacy" 'LetAppsGetDiagnosticInfo' 2
Add-Reg  Standard "$P\Speech" 'AllowSpeechModelUpdate' 0;          Tag 'voice'
Add-UReg Standard 'Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1
Add-Svc  Standard 'PNRPAutoReg'

# --- Standard: additional telemetry pipeline controls (freddie-o 08.27.2026, EXLOUD, win-baseline) --
$DC  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
$DT  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack'
$ACF = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags'
Add-Reg  Standard $DC 'MaxTelemetryAllowed' '@Telemetry'
Add-Reg  Standard 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' '@Telemetry'
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\System\AllowTelemetry' 'value' '@Telemetry'
Add-Reg  Standard "$PW\DataCollection" 'AllowUpdateComplianceProcessing' 0
Add-Reg  Standard "$PW\DataCollection" 'AllowWUfBCloudProcessing' 0
Add-Reg  Standard "$PW\DataCollection" 'MicrosoftEdgeDataOptIn' 0
Add-Reg  Standard "$PW\DataCollection" 'DisableTelemetryOptInSettingsUx' 1
Add-Reg  Standard "$PW\DataCollection" 'EnableExtendedBooksTelemetry' 0
Add-Reg  Standard $DT 'AllowDiagnosticSubmission' 0;                     Tag 'telemetry-service'
Add-Reg  Standard $DT 'DownloadSettings' 0;                              Tag 'onesettings'
Add-Reg  Standard "$DT\EventTranscriptKey" 'EnableEventTranscript' 0
Add-Reg  Standard "$ACF\ClientTelemetry" 'IsCensusDisabled' 1
Add-Reg  Standard "$ACF\ClientTelemetry" 'TaskEnableRun' 0
Add-Reg  Standard "$ACF\ClientTelemetry" 'DontRetryOnError' 1
Add-Reg  Standard "$ACF\TelemetryController" 'RunsBlocked' 1
Add-Reg  Standard "$ACF\AIT" 'AITEnable' 0
foreach ($sqm in 'Windows', 'IE', 'Reliability') { Add-Reg Standard "HKLM:\SOFTWARE\Microsoft\SQMClient\$sqm" 'CEIPEnable' 0 }
Add-Def Standard 'Reg' @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\SetupPlatformTel'; Name = 'Start'; Value = 0; OnlyIfExists = $true }
foreach ($n in 'TelemetryPerformanceEnabled', 'TelemetryErrorDataEnabled', 'TelemetryDeviceHealthEnabled') {
    Add-Reg Standard 'HKLM:\SYSTEM\CurrentControlSet\Control\StorPort' $n 0
}
Add-Reg  Standard "$PW\StorageHealth" 'DisableStorageHealthTelemetry' 1
Add-Reg  Standard "$PW\DeviceInstall\Settings" 'DisableSendGenericDriverNotFoundToWER' 1
Add-Reg  Standard "$PW\ScriptedDiagnosticsProvider\Policy" 'DisableQueryRemoteServer' 1
Add-Reg  Standard "$PW\OOBE" 'DisablePrivacyExperience' 1
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\System' 'AllowExperimentation' 0
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput' 'AllowLinguisticDataCollection' 0
Add-Reg  Standard "$P\EventViewer" 'MicrosoftEventVwrDisableLinks' 1
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoInternetOpenWith' 1
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' 'value' 0
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' 'value' 0
Add-Reg  Standard "$PW\AppPrivacy" 'LetAppsAccessAdvertisingId' 2
Add-Reg  Standard "$PW\Windows Search" 'AllowSearchToUseLocation' 0
Add-Reg  Standard "$PW\Windows Search" 'ConnectedSearchUseWebOverMeteredConnections' 0
Add-Reg  Standard "$IFEO\aggregatorhost.exe" 'Debugger' '%SystemRoot%\System32\cmd.exe /c exit' 'String'
Add-Svc  Standard 'InventorySvc'
Add-Svc  Standard 'wisvc'
Add-Svc  Standard 'WpcMonSvc'
Add-Svc  Standard 'diagnosticshub.standardcollector.service';            Tag 'dev'
foreach ($tk in @(
        '\Microsoft\Windows\Application Experience\|AITAgent'
        '\Microsoft\Windows\Customer Experience Improvement Program\|BthSQM'
        '\Microsoft\Windows\CloudExperienceHost\|CreateObjectTask'
        '\Microsoft\Windows\Diagnosis\|Scheduled'
        '\Microsoft\Windows\Flighting\FeatureConfig\|UsageDataFlushing'
        '\Microsoft\Windows\NetTrace\|GatherNetworkInfo'
        '\Microsoft\Windows\PI\|Sqm-Tasks'
        '\Microsoft\Windows\Power Efficiency Diagnostics\|AnalyzeSystem'
        '\Microsoft\Windows\User Profile Service\|HiveUploadTask')) {
    $parts = $tk.Split('|')
    Add-Task Standard $parts[0] $parts[1]
}
Add-Task Standard '\Microsoft\Windows\Speech\' 'SpeechModelDownloadTask';   Tag 'voice'
Add-Task Standard '\Microsoft\Windows\Flighting\OneSettings\' 'RefreshCache';  Tag 'onesettings'
Add-Reg  Standard "$P\SQMClient\Windows" 'CEIPEnable' 0
Add-Reg  Standard "$PW\AppCompat" 'AITEnable' 0
Add-Reg  Standard "$PW\AppCompat" 'DisableInventory' 1
Add-Reg  Standard "$PW\AppCompat" 'DisableUAR' 1
Add-Reg  Standard "$PW\Windows Error Reporting" 'DontSendAdditionalData' 1
Add-Reg  Standard "$P\MRT" 'DontReportInfectionInformation' 1
Add-Task Standard $AE 'Microsoft Compatibility Appraiser'
Add-Task Standard $AE 'Microsoft Compatibility Appraiser Exp'
Add-Task Standard $AE 'ProgramDataUpdater'
Add-Task Standard $AE 'MareBackup'
Add-Task Standard '\Microsoft\Windows\Autochk\' 'Proxy'
Add-Task Standard $CE 'Consolidator'
Add-Task Standard $CE 'UsbCeip'
Add-Task Standard $CE 'KernelCeipTask'
Add-Task Standard '\Microsoft\Windows\DiskDiagnostic\' 'Microsoft-Windows-DiskDiagnosticDataCollector'
Add-Task Standard '\Microsoft\Windows\Feedback\Siuf\' 'DmClient'
Add-Task Standard '\Microsoft\Windows\Feedback\Siuf\' 'DmClientOnScenarioDownload'
Add-Task Standard '\Microsoft\Windows\Windows Error Reporting\' 'QueueReporting'
Add-Task Standard '\Microsoft\Windows\Device Information\' 'Device'
Add-Task Standard '\Microsoft\Windows\Device Information\' 'Device User'
Add-Task Standard '\Microsoft\Windows\Flighting\FeatureConfig\' 'UsageDataReporting'
Add-FwExe Standard '%SystemRoot%\System32\CompatTelRunner.exe'
Add-FwExe Standard '%SystemRoot%\System32\DeviceCensus.exe'
Add-FwExe Standard '%SystemRoot%\System32\WerFault.exe';        Tag 'wer'
Add-FwExe Standard '%SystemRoot%\System32\wermgr.exe';          Tag 'wer'
Add-Hosts Standard 'Diag';                                       Tag 'telemetry-hosts'
Add-Hosts Standard 'GameEvents';                                 Tag 'game-events'

# --- Standard: ads, suggestions, personalization -----------------------------
Add-Reg  Standard "$PW\AdvertisingInfo" 'DisabledByGroupPolicy' 1
Add-Reg  Standard "$PW\System" 'EnableActivityFeed' 0
Add-Reg  Standard "$PW\System" 'PublishUserActivities' 0
Add-Reg  Standard "$PW\System" 'UploadUserActivities' 0
Add-Reg  Standard "$PW\CloudContent" 'DisableWindowsConsumerFeatures' 1
Add-Reg  Standard "$PW\CloudContent" 'DisableSoftLanding' 1
Add-Reg  Standard "$PW\CloudContent" 'DisableCloudOptimizedContent' 1
Add-Reg  Standard "$PW\CloudContent" 'DisableConsumerAccountStateContent' 1
Add-Reg  Standard "$PW\TabletPC" 'PreventHandwritingDataSharing' 1
Add-Reg  Standard "$PW\HandwritingErrorReports" 'PreventHandwritingErrorReports' 1
Add-Reg  Standard "$PW\Messaging" 'AllowMessageSync' 0
Add-Reg  Standard "$P\Edge" 'DiagnosticData' 0
Add-Reg  Standard "$P\Edge" 'PersonalizationReportingEnabled' 0
Add-Reg  Standard "$P\InputPersonalization" 'AllowInputPersonalization' 0;          Tag 'voice'
# Per-user equivalents (the only ones Home/Pro honour for several of the above)
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
Add-UReg Standard 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
Add-UReg Standard $CDM 'SilentInstalledAppsEnabled' 0
Add-UReg Standard $CDM 'SystemPaneSuggestionsEnabled' 0
Add-UReg Standard $CDM 'SoftLandingEnabled' 0
Add-UReg Standard $CDM 'SubscribedContent-338388Enabled' 0
Add-UReg Standard $CDM 'SubscribedContent-338389Enabled' 0
Add-UReg Standard $CDM 'SubscribedContent-353694Enabled' 0
Add-UReg Standard $CDM 'SubscribedContent-353696Enabled' 0
Add-UReg Standard 'Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
Add-UReg Standard 'Software\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0
foreach ($n in 'ContentDeliveryAllowed', 'FeatureManagementEnabled', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
        'PreInstalledAppsEverEnabled', 'SubscribedContentEnabled', 'SubscribedContent-353698Enabled') {
    Add-UReg Standard $CDM $n 0
}
Add-UReg Standard 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1
Add-UReg Standard 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightOnActionCenter' 1
Add-UReg Standard 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightOnSettings' 1
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Id' '00000000-0000-0000-0000-000000000000' 'String'
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0
Add-UReg Standard 'Software\Microsoft\Input\TIPC' 'Enabled' 0
Add-UReg Standard 'Software\Microsoft\Input\Settings' 'InsightsEnabled' 0
Add-UReg Standard 'Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
Add-UReg Standard 'Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0;   Tag 'voice'
foreach ($n in 'IsMSACloudSearchEnabled', 'IsAADCloudSearchEnabled', 'IsDeviceSearchHistoryEnabled') {
    Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\SearchSettings' $n 0
}
# Windows Spotlight: blocked at every tier, no Keep switch.
Add-UReg Standard $CDM 'RotatingLockScreenEnabled' 0
Add-UReg Standard $CDM 'RotatingLockScreenOverlayEnabled' 0
Add-UReg Standard $CDM 'SubscribedContent-338387Enabled' 0
Add-UReg Standard 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1
Add-UReg Standard 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableSpotlightCollectionOnDesktop' 1
Add-UReg Standard 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1
Add-UReg Standard 'Software\Policies\Microsoft\Windows\CloudContent' 'ConfigureWindowsSpotlight' 2
# Widgets / News and Interests, search highlights, Start recommendations: the components
# that pull MSN/Bing content (and with it Comscore/OneTrust beacons) on a fresh install.
Add-Reg  Standard "$P\Dsh" 'AllowNewsAndInterests' 0
Add-Reg  Standard "$PW\Windows Feeds" 'EnableFeeds' 0
Add-Reg  Standard "$PW\Windows Search" 'EnableDynamicContentInWSB' 0
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0
Add-Hosts Standard 'Trackers'
Add-UReg Standard 'Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
Add-UReg Standard 'Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
Add-UReg Standard 'Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0;  Tag 'voice'
Add-Hosts Standard 'Ads'

# --- Standard: Office and developer tools ------------------------------------
# Client-side opt-outs never break anything, so they apply even with the Keep switches.
Add-UReg Standard 'Software\Policies\Microsoft\office\common\clienttelemetry' 'sendtelemetry' 3
Add-UReg Standard 'Software\Policies\Microsoft\office\16.0\common\clienttelemetry' 'DisableTelemetry' 1
Add-Reg  Standard "$P\VisualStudio\SQM" 'OptIn' 0
Add-Reg  Standard $ENV 'DOTNET_CLI_TELEMETRY_OPTOUT' '1' 'String'
Add-Reg  Standard $ENV 'POWERSHELL_TELEMETRY_OPTOUT' '1' 'String'
Add-Hosts Standard 'Office';                                     Tag 'office'
Add-Hosts Standard 'Dev';                                        Tag 'dev'

# --- Maximum (and Gaming) -----------------------------------------------------
Add-Svc  Maximum 'CDPSvc';                                        Tag 'cdp'
Add-Svc  Maximum 'CDPUserSvc';                                    Tag 'cdp'
Add-FwSvc Maximum 'CDPSvc';                                       Tag 'cdp'
Add-Reg  Maximum "$PW\System" 'EnableCdp' 0;                      Tag 'cdp'
Add-Reg  Maximum "$PW\System" 'EnableMmx' 0;                      Tag 'cdp'
Add-Reg  Maximum "$PW\System" 'AllowCrossDeviceClipboard' 0;      Tag 'cdp'
Add-Hosts Maximum 'Graph';                                        Tag 'cdp'
Add-Reg  Maximum "$PW\DeliveryOptimization" 'DODownloadMode' 99;  Tag 'store'   # Simple: no peering, no DO cloud
Add-Hosts Maximum 'DO';                                           Tag 'store'
Add-Reg  Standard "$PW\Windows Search" 'AllowCortana' 0
Add-Reg  Standard "$PW\Windows Search" 'AllowCloudSearch' 0
Add-Reg  Standard "$PW\Windows Search" 'ConnectedSearchUseWeb' 0
Add-Reg  Standard "$PW\Windows Search" 'DisableWebSearch' 1
Add-UReg Standard 'Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
Add-Reg  Maximum "$PW\SettingSync" 'DisableSettingSync' 2
Add-Reg  Maximum "$PW\SettingSync" 'DisableSettingSyncUserOverride' 1
Add-Reg  Standard "$PW\WindowsCopilot" 'TurnOffWindowsCopilot' 1
Add-UReg Standard 'Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
Add-Reg  Standard "$PW\WindowsAI" 'DisableAIDataAnalysis' 1
Add-Reg  Standard "$PW\WindowsAI" 'AllowRecallEnablement' 0
Add-Reg  Standard "$PW\WindowsAI" 'TurnOffSavingSnapshots' 1
Add-Reg  Standard "$PW\WindowsAI" 'DisableClickToDo' 1
Add-Reg  Standard "$PW\WindowsAI" 'DisableSettingsAgent' 1
Add-Reg  Standard "$PW\WindowsCopilot" 'AllowWindowsCopilot' 0
Add-UReg Standard 'Software\Policies\Microsoft\Windows\WindowsCopilot' 'AllowWindowsCopilot' 0
Add-Reg  Standard "$PW\AppPrivacy" 'LetAppsAccessGenerativeAI' 2
Add-Reg  Standard "$PW\AppPrivacy" 'LetAppsAccessSystemAIModels' 2

# Connectivity check (NCSI): swap Microsoft's probe servers for GNOME's NetworkManager check
# (web) and Cloudflare's one.one.one.one (DNS) so the network icon, "am I online" checks in
# apps and captive-portal detection keep working without contacting Microsoft. Not
# NoActiveProbe: that policy overrides these values and makes Windows report "No Internet".
$NI = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
Add-Reg  Standard $NI 'ActiveWebProbeHost'      'nmcheck.gnome.org'        'String'
Add-Reg  Standard $NI 'ActiveWebProbePath'      'check_network_status.txt' 'String'
Add-Reg  Standard $NI 'ActiveWebProbeContent'   'NetworkManager is online' 'String'
Add-Reg  Standard $NI 'ActiveWebProbeHostV6'    'nmcheck.gnome.org'        'String'
Add-Reg  Standard $NI 'ActiveWebProbePathV6'    'check_network_status.txt' 'String'
Add-Reg  Standard $NI 'ActiveWebProbeContentV6' 'NetworkManager is online' 'String'
Add-Reg  Standard $NI 'ActiveDnsProbeHost'      'one.one.one.one'          'String'
Add-Reg  Standard $NI 'ActiveDnsProbeContent'   '1.1.1.1'                  'String'
Add-Reg  Standard $NI 'ActiveDnsProbeHostV6'    'one.one.one.one'          'String'
Add-Reg  Standard $NI 'ActiveDnsProbeContentV6' '2606:4700:4700::1111'     'String'
Add-Hosts Standard 'Ncsi'

# --- Standard: remaining telemetry switches (EXLOUD / freddie-o cross-check) ---
# Telemetry service internals (undocumented; skipped in Gaming, which needs the service).
$DT = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack'
Add-Reg  Standard $DT 'DiagTrackAuthorization' 0;                               Tag 'telemetry-service'
Add-Reg  Standard $DT 'UploadPermissionReceived' 0;                             Tag 'telemetry-service'
Add-Reg  Standard $DT 'TelemetryServiceDisabled' 1;                             Tag 'telemetry-service'
Add-Reg  Standard $DT 'DisableAutomaticTelemetryKeywordReporting' 1;            Tag 'telemetry-service'
Add-Reg  Standard "$DT\TestHooks" 'DisableAsimovUpload' 1;                      Tag 'telemetry-service'
Add-Reg  Standard "$DT\TraceManager" 'MiniTraceSlotEnabled' 0;                  Tag 'telemetry-service'
# CEIP opt-in prompt; PerfTrack responsiveness telemetry scenario.
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows' 'DisableOptinExperience' 1
Add-Reg  Standard "$PW\WDI\{9c5a40da-b965-4fc3-8781-88dd50a6299d}" 'ScenarioExecutionEnabled' 0
# Help / tips feedback and online tips in Settings.
Add-Reg  Standard "$P\Assistance\Client\1.0" 'NoActiveHelp' 1
Add-Reg  Standard "$P\Assistance\Client\1.0" 'NoExplicitFeedback' 1
Add-Reg  Standard "$P\Assistance\Client\1.0" 'NoImplicitFeedback' 1
Add-UReg Standard 'Software\Policies\Microsoft\Assistance\Client\1.0' 'NoExplicitFeedback' 1
Add-UReg Standard 'Software\Policies\Microsoft\Assistance\Client\1.0' 'NoImplicitFeedback' 1
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'AllowOnlineTips' 0
# Typing language-model data logger (typing insights are already off).
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Input\Settings' 'LMDataLoggerEnabled' 0
# Error-report SENDING only. Local crash dumps are untouched.
Add-Reg  Standard "$PW\Windows Error Reporting" 'AutoApproveOSDumps' 0;  Tag 'wer'
Add-Reg  Standard "$PW\Windows Error Reporting" 'BypassDataThrottling' 0;  Tag 'wer'
Add-Reg  Standard "$PW\Windows Error Reporting" 'DoReport' 0;  Tag 'wer'
Add-Reg  Standard "$P\PCHealth\ErrorReporting" 'DoReport' 0;  Tag 'wer'
# Windows Media Player usage tracking, user GUID and online metadata lookups.
Add-UReg Standard 'Software\Microsoft\MediaPlayer\Preferences' 'UsageTracking' 0
Add-UReg Standard 'Software\Microsoft\MediaPlayer\Preferences' 'SendUserGUID' 0
Add-UReg Standard 'Software\Policies\Microsoft\WindowsMediaPlayer' 'PreventCDDVDMetadataRetrieval' 1
Add-UReg Standard 'Software\Policies\Microsoft\WindowsMediaPlayer' 'PreventMusicFileMetadataRetrieval' 1
Add-UReg Standard 'Software\Policies\Microsoft\WindowsMediaPlayer' 'PreventRadioPresetsRetrieval' 1
# Spotlight (no opt-out): enterprise Spotlight too. Wi-Fi Sense (Windows 10).
Add-UReg Standard 'Software\Policies\Microsoft\Windows\CloudContent' 'IncludeEnterpriseSpotlight' 0
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' 'WiFISenseAllowed' 0
# Disk usage telemetry task.
Add-TaskF Standard '\Microsoft\Windows\DiskFootprint\'
# Store remote installs pushed from your account (accounts are blocked at these tiers anyway).
Add-TaskF Maximum '\Microsoft\Windows\PushToInstall\';                       Tag 'store'
Add-TaskF Maximum '\Microsoft\Windows\InstallService\';                      Tag 'store'

# --- Standard: Cortana (the app itself is removed in Invoke-Enforce) -----------
Add-Reg  Standard "$PW\Windows Search" 'AllowCortanaAboveLock' 0
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0

# --- Flag: NoSearch (-DisableSearch, opt-in) ------------------------------------
# Indexer off; Start/taskbar search UI blocked (Win10 SearchApp/SearchUI, Win11 SearchHost).
Add-Svc  Standard 'WSearch' 'NoSearch'
Add-Reg  Standard "$IFEO\SearchApp.exe"  'Debugger' '%SystemRoot%\System32\cmd.exe /c exit' 'String' 'NoSearch'
Add-Reg  Standard "$IFEO\SearchUI.exe"   'Debugger' '%SystemRoot%\System32\cmd.exe /c exit' 'String' 'NoSearch'
Add-Reg  Standard "$IFEO\SearchHost.exe" 'Debugger' '%SystemRoot%\System32\cmd.exe /c exit' 'String' 'NoSearch'
Add-Def  Standard 'UserReg' @{ Path = 'Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'SearchboxTaskbarMode'; Value = 0 } 'NoSearch'

# --- Standard: Office privacy controls (-KeepOffice) -------------------------
$OP = 'Software\Policies\Microsoft\office\16.0\common'
Add-UReg Standard "$OP\privacy" 'controllerconnectedservicesenabled' 2;       Tag 'office'
Add-UReg Standard $OP 'qmenable' 0;                                             Tag 'office'
Add-UReg Standard $OP 'sendcustomerdata' 0;                                     Tag 'office'
Add-UReg Standard "$OP\feedback" 'enabled' 0;                                  Tag 'office'
Add-UReg Standard "$OP\feedback" 'includescreenshot' 0;                        Tag 'office'
Add-UReg Standard "$OP\feedback" 'surveyenabled' 0;                            Tag 'office'
# Maximum: content-analysing (Designer, Editor) and online-content (templates, icons) experiences.
Add-UReg Maximum "$OP\privacy" 'usercontentdisabled' 2;                        Tag 'office'
Add-UReg Maximum "$OP\privacy" 'downloadcontentdisabled' 2;                    Tag 'office'

# --- Flag: GpuTel (-BlockGpuTelemetry, opt-in) -----------------------------------
# NVIDIA (keys only touched if the driver created them), AMD UEP, Intel CIP.
Add-Svc  Standard 'NvTelemetryContainer' 'GpuTel'
Add-Def  Standard 'Reg' @{ Path = 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client'; Name = 'OptInOrOutPreference'; Value = 0; OnlyIfExists = $true } 'GpuTel'
Add-Def  Standard 'Reg' @{ Path = 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS'; Name = 'EnableRID44231'; Value = 0; OnlyIfExists = $true } 'GpuTel'
Add-Def  Standard 'Reg' @{ Path = 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS'; Name = 'EnableRID64640'; Value = 0; OnlyIfExists = $true } 'GpuTel'
Add-Def  Standard 'Reg' @{ Path = 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS'; Name = 'EnableRID66610'; Value = 0; OnlyIfExists = $true } 'GpuTel'
Add-Def  Standard 'Reg' @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\Startup'; Name = 'SendTelemetryData'; Value = 0; OnlyIfExists = $true } 'GpuTel'
Add-Hosts Standard 'GpuTelemetry' 'GpuTel'
Add-Reg  Standard "$IFEO\AUEPLauncher.exe" 'Debugger' '%SystemRoot%\System32\cmd.exe /c exit' 'String' 'GpuTel'
Add-Reg  Standard "$IFEO\AUEPMaster.exe"   'Debugger' '%SystemRoot%\System32\cmd.exe /c exit' 'String' 'GpuTel'
Add-Svc  Standard 'SystemUsageReportSvc_QUEENCREEK' 'GpuTel'
Add-Svc  Standard 'ESRV_SVC_QUEENCREEK' 'GpuTel'
Add-Svc  Standard 'USER_ESRV_SVC_QUEENCREEK' 'GpuTel'

# --- Standard: location off (-KeepLocation) ---------------------------------
# Includes the automatic time zone service, which only works through location.
Add-Svc  Standard 'lfsvc';                                       Tag 'location'
Add-Reg  Standard "$PW\LocationAndSensors" 'DisableLocation' 1;  Tag 'location'
Add-Hosts Standard 'Location';                                    Tag 'location'
Add-Reg  Standard "$PW\LocationAndSensors" 'DisableLocationScripting' 1;        Tag 'location'
Add-Reg  Standard "$PW\LocationAndSensors" 'DisableWindowsLocationProvider' 1;  Tag 'location'
Add-Reg  Standard "$P\FindMyDevice" 'AllowFindMyDevice' 0;                       Tag 'location'
Add-Svc  Standard 'MapsBroker';                                                  Tag 'location'
Add-TaskF Standard '\Microsoft\Windows\Location\';                               Tag 'location'
Add-TaskF Standard '\Microsoft\Windows\Maps\';                                   Tag 'location'
Add-Svc  Standard 'tzautoupdate';                                                Tag 'location'

# --- Windows 11 features that depend on what this script turns off ------------
# No effect on Windows 10: the values are only read where the feature exists.
# AI (Recall, Notepad/Paint cloud AI) - Copilot/Recall are off at every tier.
Add-Reg  Standard "$PW\WindowsAI" 'DisableRecallDataProviders' 1
Add-Reg  Standard "$PW\Recall" 'DisableRecall' 1
Add-Reg  Standard "$PW\Recall" 'DisableSnapshotSave' 1
Add-Reg  Standard 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableCocreator' 1
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableGenerativeFill' 1
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableImageCreator' 1
# Widgets are off; lock-screen weather/news widgets use the same feed (and location).
Add-Reg  Standard "$P\Dsh" 'DisableWidgetsOnLockScreen' 1
# Cloud / Microsoft Graph content in Start and File Explorer Home (Graph is hosts-blocked at Maximum).
Add-Reg  Standard "$PW\Explorer" 'HideRecommendedPersonalizedSites' 1
Add-Reg  Standard "$PW\Explorer" 'DisableGraphRecentItems' 1
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowCloudFilesInQuickAccess' 0
# "Let's finish setting up your device" (Microsoft account, OneDrive, Phone Link upsell).
Add-UReg Standard 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
# Microsoft account sign-in / backup nags in Start and Settings, when accounts are blocked.
Add-Def  Standard 'UserReg' @{ Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_AccountNotifications'; Value = 0 } 'Mint'
Add-Def  Standard 'UserReg' @{ Path = 'Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications'; Name = 'EnableAccountNotifications'; Value = 0 } 'Mint'
# SmartScreen for Store-app web content, when SmartScreen is off.
Add-Def  Standard 'UserReg' @{ Path = 'Software\Microsoft\Windows\CurrentVersion\AppHost'; Name = 'EnableWebContentEvaluation'; Value = 0 } 'SmartScreen'
# "Resume" (continue a phone app on the PC) runs over the device graph that Maximum blocks.
Add-UReg Maximum 'Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration' 'IsResumeAllowed' 0;  Tag 'cdp'

# --- Maximum ------------------------------------------------------------------
Add-Svc  Maximum 'OneSyncSvc'
Add-Svc  Maximum 'diagsvc'
Add-Task Maximum '\Microsoft\Windows\International\' 'Synchronize Language Settings'
Add-Reg  Maximum "$PW\DataCollection" 'DisableOneSettingsDownloads' 1;              Tag 'onesettings'
Add-Hosts Maximum 'OneSettings';                                  Tag 'onesettings'
Add-Hosts Maximum 'ECS';                                          Tag 'office'

# --- Stripped (Defender / Windows Update removed builds) ----------------------
Add-Svc  Stripped 'wuauserv';                                    Tag 'store'
Add-Svc  Stripped 'DoSvc';                                       Tag 'store'
Add-Svc  Stripped 'UsoSvc'
Add-Svc  Stripped 'WaaSMedicSvc'
Add-Svc  Stripped 'uhssvc'
Add-TaskF Stripped '\Microsoft\Windows\UpdateOrchestrator\'
Add-TaskF Stripped '\Microsoft\Windows\WindowsUpdate\'
Add-TaskF Stripped '\Microsoft\Windows\WaaSMedic\'
Add-Reg  Stripped "$PW\WindowsUpdate\AU" 'NoAutoUpdate' 1
Add-Reg  Stripped "$PW\WindowsUpdate" 'SetDisableUXWUAccess' 1
Add-Reg  Stripped "$PW\WindowsUpdate" 'DoNotConnectToWindowsUpdateInternetLocations' 1;  Tag 'store'
Add-Reg  Stripped "$PW\WindowsUpdate" 'DisableWindowsUpdateAccess' 1;                   Tag 'store'
Add-Reg  Stripped "$P\MRT" 'DontOfferThroughWUAU' 1
Add-Reg  Stripped "$PW\DriverSearching" 'DontSearchWindowsUpdate' 1
foreach ($exe in 'SIHClient.exe', 'WaaSMedicAgent.exe', 'UsoClient.exe') {
    Add-Reg Stripped "$IFEO\$exe" 'Debugger' '%SystemRoot%\System32\cmd.exe /c exit' 'String'
}
Add-FwSvc Stripped 'wuauserv';                                   Tag 'store'
Add-FwSvc Stripped 'UsoSvc'
Add-FwExe Stripped '%SystemRoot%\System32\SIHClient.exe'
Add-FwExe Stripped '%SystemRoot%\System32\MoUsoCoreWorker.exe'
Add-FwExe Stripped '%SystemRoot%\System32\usocoreworker.exe'
Add-Hosts Stripped 'Update';                                     Tag 'store'

# --- Flag: SmartScreen (Standard/Gaming unless -KeepSmartScreen; forced at Maximum, Stripped)
Add-Reg  Standard "$PW\System" 'EnableSmartScreen' 0 'DWord' 'SmartScreen'
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled' 'Off' 'String' 'SmartScreen'
Add-Reg  Standard "$P\Edge" 'SmartScreenEnabled' 0 'DWord' 'SmartScreen'
Add-FwExe Standard '%SystemRoot%\System32\smartscreen.exe' 'SmartScreen'
Add-Hosts Standard 'SmartScreen' 'SmartScreen'
Add-Task Standard '\Microsoft\Windows\AppID\' 'SmartScreenSpecific' 'SmartScreen'

# --- Maximum (and Gaming, Stripped): Defender cloud protection (MAPS) off. ---------
#     Sends file metadata and samples to Microsoft. With Tamper Protection on, Windows may
#     ignore the two policies; the hosts block stops the lookups either way. Defender's
#     local scanning and definition updates are unaffected. Standard leaves it on.
Add-Reg  Maximum "$P\Windows Defender\Spynet" 'SpynetReporting' 0
Add-Reg  Maximum "$P\Windows Defender\Spynet" 'SubmitSamplesConsent' 2
Add-Hosts Maximum 'Defender'

# --- Flag: GameOn (Gaming tier, -KeepGaming, Temp Unlock) ----------------------
# Actively undo common debloat settings that cause Forza Horizon 6 E:0-17: the save
# folder is provisioned by Gaming Services from OneSettings, which DiagTrack downloads.
# E:0-23-8 ("Initialization failed"): the game needs Connected User Experiences and
# Telemetry plus the Xbox / Gaming Services stack enabled. Start = value set only if the
# service was Disabled (4); services already Manual/Automatic are left at their setting.
foreach ($s in @(
        @{ Name = 'DiagTrack';         Start = 2 }
        @{ Name = 'GamingServices';    Start = 2 }
        @{ Name = 'GamingServicesNet'; Start = 2 }
        @{ Name = 'XblAuthManager';    Start = 3 }
        @{ Name = 'XblGameSave';       Start = 3 }
        @{ Name = 'XboxNetApiSvc';     Start = 3 }
        @{ Name = 'XboxGipSvc';        Start = 3 })) {
    Add-Def Standard 'ServiceOn' $s 'GameOn'
}
Add-Reg  Standard "$PW\DataCollection" 'DisableOneSettingsDownloads' 0 'DWord' 'GameOn'
Add-Reg  Standard "$PW\DataCollection" 'LimitDiagnosticLogCollection' 0 'DWord' 'GameOn'

# --- Standard: Windows Hello off (-KeepHello) ---------------------------------
Add-Reg  Standard "$P\PassportForWork" 'Enabled' 0;                            Tag 'hello'
Add-Reg  Standard "$P\PassportForWork" 'DisablePostLogonProvisioning' 1;       Tag 'hello'
Add-Reg  Standard "$P\Biometrics" 'Enabled' 0;                                 Tag 'hello'
Add-Reg  Standard "$PW\System" 'AllowDomainPINLogon' 0;                        Tag 'hello'
# Turns off "only allow Windows Hello sign-in for Microsoft accounts" so the password option returns.
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' 'DevicePasswordLessBuildVersion' 0;  Tag 'hello'

# --- Standard: OneDrive off (-KeepOneDrive) -----------------------------------
Add-Reg  Standard "$PW\OneDrive" 'DisableFileSyncNGSC' 1;                      Tag 'onedrive'
Add-Reg  Standard "$PW\OneDrive" 'DisableLibrariesDefaultSaveToOneDrive' 1;    Tag 'onedrive'
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\OneDrive' 'PreventNetworkTrafficPreUserSignIn' 1;  Tag 'onedrive'
Add-Reg  Standard "$IFEO\OneDriveSetup.exe" 'Debugger' '%SystemRoot%\System32\cmd.exe /c exit' 'String';  Tag 'onedrive'

# --- Standard: Edge sign-in / sync off (-KeepEdgeSync) ------------------------
Add-Reg  Standard "$P\Edge" 'SyncDisabled' 1;                                   Tag 'edgesync'
Add-Reg  Standard "$P\Edge" 'BrowserSignin' 0;                                  Tag 'edgesync'
Add-Reg  Standard "$P\Edge" 'StartupBoostEnabled' 0;                            Tag 'edgesync'
Add-Reg  Standard "$P\Edge" 'BackgroundModeEnabled' 0;                          Tag 'edgesync'

# --- Flag: NoEdge (every tier unless -KeepEdge)
# Edge Update app IDs: Edge Stable {56EB18F8-...}. WebView2 {F3017226-...} is deliberately untouched.
Add-Reg  Standard "$P\EdgeUpdate" 'Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' 0 'DWord' 'NoEdge'

# --- Flag: GDID mint (breaks Microsoft accounts) ------------------------------
Add-FwSvc Standard 'wlidsvc' 'Mint'
Add-Hosts Standard 'Mint' 'Mint';                                Tag 'dev'
# "Accounts: Block Microsoft accounts" = users can't add or log on with Microsoft accounts.
Add-Reg  Standard 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'NoConnectedUser' 3 'DWord' 'Mint'
