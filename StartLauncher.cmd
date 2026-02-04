@echo off
setlocal

REM Va dans le dossier du script (important)
cd /d "%~dp0"

REM Enlève le blocage Windows si le zip vient d'internet
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-ChildItem -Recurse -File | Unblock-File" >nul 2>&1

REM Autorise les scripts pour cet utilisateur (sans admin)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch {}" >nul 2>&1

REM Lance ton launcher
powershell -NoProfile -ExecutionPolicy Bypass -File ".\MonkeyDLauncher.ps1"

endlocal
