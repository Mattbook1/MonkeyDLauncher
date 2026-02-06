@echo off
setlocal
cd /d "%~dp0"

:: 1) Créer le raccourci "MonkeyD.Launcher" si absent
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws = New-Object -ComObject WScript.Shell; " ^
  "$desk = [Environment]::GetFolderPath('Desktop'); " ^
  "$lnkPath = Join-Path $desk 'MonkeyD.Launcher.lnk'; " ^
  "if (!(Test-Path $lnkPath)) { " ^
  "  $s = $ws.CreateShortcut($lnkPath); " ^
  "  $s.TargetPath = 'powershell.exe'; " ^
  "  $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%~dp0MonkeyDLauncher.ps1""'; " ^
  "  $s.WorkingDirectory = '%~dp0'; " ^
  "  if (Test-Path '%~dp0MonkeyD_Launcher.ico') { $s.IconLocation = '%~dp0MonkeyD_Launcher.ico,0' } " ^
  "  $s.Save() " ^
  "}"

:: 2) Lancer le launcher
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MonkeyDLauncher.ps1"
endlocal
exit


