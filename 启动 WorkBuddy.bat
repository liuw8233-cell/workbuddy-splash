@echo off
setlocal
cd /d "%~dp0"

rem Everything (browser + WorkBuddy) is auto-detected inside launcher.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher.ps1"

if errorlevel 1 pause
endlocal
