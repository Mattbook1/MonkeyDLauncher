@echo off
setlocal

cd /d "%~dp0"

:: Lancer MonkeyDLauncher.ps1 simplement
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MonkeyDLauncher.ps1"

exit


