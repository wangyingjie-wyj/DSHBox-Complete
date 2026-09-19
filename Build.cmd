@echo off
setlocal
cd /d "%~dp0"
set "SKIP_PAUSE="
for %%A in (%*) do if /I "%%~A"=="-NoPause" set "SKIP_PAUSE=1"
if defined SKIP_PAUSE (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build.ps1" %*
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build.ps1" -NoPause %*
)
set "BUILD_EXIT=%ERRORLEVEL%"
echo.
if "%BUILD_EXIT%"=="0" (echo Build command completed successfully.) else (echo Build command FAILED. See the error above.)
if not defined SKIP_PAUSE pause
exit /b %BUILD_EXIT%
