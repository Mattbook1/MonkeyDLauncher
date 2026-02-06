@echo off
setlocal

REM Se placer dans le dossier du launcher
cd /d "%~dp0"

REM ---------- Créer / corriger le raccourci ----------
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$ws = New-Object -ComObject WScript.Shell; ^
$desktop = [Environment]::GetFolderPath('Desktop'); ^
$link = Join-Path $desktop 'MonkeyD.Launcher.lnk'; ^
$sc = $ws.CreateShortcut($link); ^
$sc.TargetPath = 'powershell.exe'; ^
$sc.Arguments = '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0MonkeyDLauncher.ps1""'; ^
$sc.WorkingDirectory = '%~dp0'; ^
$sc.IconLocation = '%~dp0MonkeyD_Launcher.ico,0'; ^
$sc.Save()"

REM ---------- Lancer le launcher ----------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MonkeyDLauncher.ps1"

endlocal
exit

