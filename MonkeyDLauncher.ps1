# ===== AUTO UPDATE =====

$localVersion = "1.0.0"
$versionUrl   = "https://raw.githubusercontent.com/Mattbook1/MonkeyDLauncher/main/version.txt"
$scriptUrl    = "https://raw.githubusercontent.com/TONPSEUDO/MonkeyDLauncher/main/MonkeyDLauncher.ps1"

try {
    $onlineVersion = Invoke-RestMethod $versionUrl -UseBasicParsing

    if ($onlineVersion -ne $localVersion) {
        $res = [System.Windows.Forms.MessageBox]::Show(
            "Nouvelle version dispo ($onlineVersion). Mettre a jour ?",
            "Mise a jour",
            "YesNo",
            "Information"
        )

        if ($res -eq "Yes") {
            Invoke-WebRequest $scriptUrl -OutFile "$PSScriptRoot\MonkeyDLauncher.ps1"
            [System.Windows.Forms.MessageBox]::Show(
                "Mise a jour terminee. Relance le launcher.",
                "OK",
                "OK",
                "Information"
            )
            exit
        }
    }
}
catch {
    # silence = pas bloquant si internet HS
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================
# Monkey D. Launcher
# Auto-detection (folders = games)
# by Mattbook
# =========================

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Dossiers à ignorer
$ignoredFolders = @("Server", "User Music")

# --------- Fonctions ---------

function Get-GamesFolders {
  Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object {
    $name = $_.Name
    if ($ignoredFolders -contains $name) { return $false }
    if ($name -match "^MonkeyD") { return $false }
    return $true
  }
}

function Get-BestExe($gamePath) {
  $bad = @("\install\", "\setup\", "\redist\", "\_commonredist\", "\dotnet\", "\directx\", "\vcredist\", "\unins")
  Get-ChildItem -Path $gamePath -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue |
    Where-Object {
      $p = $_.FullName.ToLower()
      ($bad | Where-Object { $p.Contains($_) }).Count -eq 0
    } | Select-Object -First 1
}

# ✅ FIX Vintage Story (force le bon exe)
function Get-VintageStoryExe($gamePath) {
  if (!(Test-Path $gamePath)) { return $null }

  # Priorités (client d'abord)
  $candidates = @(
    "Vintagestory.exe",
    "VintagestoryClient.exe",
    "VintageStory.exe",
    "VintageStoryClient.exe"
  )

  foreach ($name in $candidates) {
    $p = Join-Path $gamePath $name
    if (Test-Path $p) { return Get-Item $p }
  }

  # Sinon : fallback (mais propre) -> cherche Vintagestory*.exe en évitant les dossiers pourris
  $bad = @("\install\", "\setup\", "\redist\", "\_commonredist\", "\dotnet\", "\directx\", "\vcredist\", "\unins")
  $exes = Get-ChildItem -Path $gamePath -Recurse -Filter "Vintagestory*.exe" -File -ErrorAction SilentlyContinue |
    Where-Object {
      $p = $_.FullName.ToLower()
      ($bad | Where-Object { $p.Contains($_) }).Count -eq 0 -and
      -not $p.Contains("server") -and
      -not $p.Contains("modmaker")
    }

  # client avant server
  $pick = $exes | Where-Object { $_.Name.ToLower().Contains("client") } | Select-Object -First 1
  if (-not $pick) { $pick = $exes | Select-Object -First 1 }
  return $pick
}

function Start-GameSafe($exe, $dir, $name) {
  try {
    Start-Process -FilePath $exe -WorkingDirectory $dir | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show(
      "Impossible de lancer $name`nDetail: $($_.Exception.Message)",
      "Erreur",
      "OK",
      "Error"
    ) | Out-Null
  }
}

# --------- UI ---------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Monkey D. Launcher"
$form.ClientSize = New-Object System.Drawing.Size(960, 540)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::Black
# --- Icône du launcher ---
$iconPath = Join-Path $root "MonkeyD_Launcher.ico"
if (Test-Path $iconPath) {
  $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
}
# Fond
$bg = Join-Path $root "MonkeyDLauncher_BG.png"
if (Test-Path $bg) {
  $form.BackgroundImage = [System.Drawing.Image]::FromFile($bg)
  $form.BackgroundImageLayout = "Stretch"
}

# Status
$status = New-Object System.Windows.Forms.Label
$status.Text = "Pret."
$status.ForeColor = [System.Drawing.Color]::White
$status.BackColor = [System.Drawing.Color]::Transparent
$status.AutoSize = $true
$form.Controls.Add($status)

# --------- BOUTONS ---------

$folders = Get-GamesFolders | Sort-Object Name

$btnW = 420
$btnH = 52
$gap  = 18

# 👉 POSITION X CENTRÉE PAR RAPPORT À LA FENÊTRE
$btnX = [int](($form.ClientSize.Width - $btnW) / 2)

$totalH = ($folders.Count * $btnH) + (($folders.Count - 1) * $gap)
$startY = [int](($form.ClientSize.Height - $totalH) / 2) + 20

$y = $startY

foreach ($f in $folders) {

  $btn = New-Object System.Windows.Forms.Button
  $btn.Text = $f.Name
  $btn.Size = New-Object System.Drawing.Size($btnW, $btnH)
  $btn.Location = New-Object System.Drawing.Point($btnX, $y)

  $btn.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
  $btn.FlatStyle = "Flat"
  $btn.FlatAppearance.BorderSize = 2
  $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(210, 200, 175, 120)
  $btn.BackColor = [System.Drawing.Color]::FromArgb(90, 60, 40, 20)
  $btn.ForeColor = [System.Drawing.Color]::FromArgb(235, 210, 160)
  $btn.Cursor = [System.Windows.Forms.Cursors]::Hand

  $btn.Add_Click({
    $path = Join-Path $root $this.Text

    # ✅ FIX UNIQUEMENT pour Vintage Story
    if ($this.Text -match "^Vintage Story") {
      $vs = Get-VintageStoryExe $path
      if ($vs) {
        $status.Text = "Lancement: $($vs.Name)"
        Start-GameSafe $vs.FullName $vs.DirectoryName $this.Text
      } else {
        [System.Windows.Forms.MessageBox]::Show(
          "Vintage Story: exe introuvable dans :`n$path",
          "Erreur",
          "OK",
          "Error"
        ) | Out-Null
      }
      return
    }

    # Autres jeux = auto normal
    $exe = Get-BestExe $path
    if ($exe) {
      $status.Text = "Lancement: $($exe.Name)"
      Start-GameSafe $exe.FullName $exe.DirectoryName $this.Text
    } else {
      [System.Windows.Forms.MessageBox]::Show(
        "Aucun exe valide dans $($this.Text)",
        "Erreur",
        "OK",
        "Error"
      ) | Out-Null
    }
  })

  $form.Controls.Add($btn)
  $y += ($btnH + $gap)
}

$form.Add_Shown({
    $h = [int]$form.ClientSize.Height
    $y = $h - 30
    $status.Location = New-Object System.Drawing.Point(20, [int]$y)
})

[void]$form.ShowDialog()
