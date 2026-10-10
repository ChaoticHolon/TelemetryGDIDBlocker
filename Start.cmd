@echo off
rem Telemetry & GDID Blocker launcher. Double-click to open the menu.
rem Uses PowerShell 7 when installed (falls back to Windows PowerShell 5.1); the script
rem asks for administrator rights itself. Arguments are passed through, e.g.:
rem   Start.cmd -Action Status
setlocal
set "SCRIPT=%~dp0Scripts\TelemetryGDIDBlocker.ps1"
if not exist "%SCRIPT%" (
    echo Cannot find "%SCRIPT%".
    pause
    exit /b 1
)
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PSEXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
) else (
    for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do if not defined FOUNDPWSH set "FOUNDPWSH=%%P"
)
if defined FOUNDPWSH set "PSEXE=%FOUNDPWSH%"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
if errorlevel 1 pause
endlocal
