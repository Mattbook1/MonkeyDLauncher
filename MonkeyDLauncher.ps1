Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===== AUTO UPDATE (NO LOOP) =====
$localVersion = "1.1.1"
$versionUrl   = "https://raw.githubusercontent.com/Mattbook1/MonkeyDLauncher/main/version.txt"
$scriptUrl    = "https://raw.githubusercontent.com/Mattbook1/MonkeyDLauncher/main/MonkeyDLauncher.ps1"

try {
    $currentScript = $MyInvocation.MyCommand.Path
    $flagPath = Join-Path $PSScriptRoot "update_once.flag"

    # si on vient JUSTE de relancer après update, on skip 1 fois
    if (Test-Path $flagPath) {
        Remove-Item $flagPath -Force -ErrorAction SilentlyContinue
    }
    else {
        # cache-buster pour éviter github cache
        $cb = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

        $onlineVersionRaw = (Invoke-RestMethod "$versionUrl?cb=$cb" -UseBasicParsing).ToString().Trim()
        $localVersionRaw  = $localVersion.ToString().Trim()

        # comparaison version safe (1.10 > 1.2)
        $onlineV = [version]$onlineVersionRaw
        $localV  = [version]$localVersionRaw

        if ($onlineV -gt $localV) {
            $res = [System.Windows.Forms.MessageBox]::Show(
                "Nouvelle version dispo ($onlineVersionRaw). Mettre a jour ?",
                "Mise a jour",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
                Invoke-WebRequest "$scriptUrl?cb=$cb" -OutFile $currentScript -UseBasicParsing

                [System.Windows.Forms.MessageBox]::Show(
                    "Mise a jour terminee. Relance automatique...",
                    "OK",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null

                # on pose un flag pour éviter de re-check direct (cache, etc.)
                New-Item -Path $flagPath -ItemType File -Force | Out-Null

                Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$currentScript`""
                exit
            }
        }
    }
}
catch {
    # silence
}
# ===== AUTO UPDATE =====

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ignoredFolders = @("Server", "User Music")

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

function Get-VintageStoryExe($gamePath) {
    if (!(Test-Path $gamePath)) { return $null }

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

    $bad = @("\install\", "\setup\", "\redist\", "\_commonredist\", "\dotnet\", "\directx\", "\vcredist\", "\unins")
    $exes = Get-ChildItem -Path $gamePath -Recurse -Filter "Vintagestory*.exe" -File -ErrorAction SilentlyContinue |
        Where-Object {
            $p = $_.FullName.ToLower()
            ($bad | Where-Object { $p.Contains($_) }).Count -eq 0 -and
            -not $p.Contains("server") -and
            -not $p.Contains("modmaker")
        }

    $pick = $exes | Where-Object { $_.Name.ToLower().Contains("client") } | Select-Object -First 1
    if (-not $pick) { $pick = $exes | Select-Object -First 1 }
    return $pick
}

function Start-GameSafe($exe, $dir, $name) {
    try { Start-Process -FilePath $exe -WorkingDirectory $dir | Out-Null }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Impossible de lancer $name`nDetail: $($_.Exception.Message)",
            "Erreur",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Load-ImageNoLock($path) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        return [System.Drawing.Image]::FromStream($ms)
    } catch { return $null }
}

function Get-GameImage($gameFolderFull) {
    # 1) image custom si dispo
    $png = Join-Path $gameFolderFull "icon.png"
    $ico = Join-Path $gameFolderFull "icon.ico"
    if (Test-Path $png) { return Load-ImageNoLock $png }
    if (Test-Path $ico) { try { return (New-Object System.Drawing.Icon($ico)).ToBitmap() } catch { } }

    # 2) icone depuis exe
    try {
        $exe = $null
        $folderName = Split-Path $gameFolderFull -Leaf

        if ($folderName -match "^Vintage Story") {
            $vs = Get-VintageStoryExe $gameFolderFull
            if ($vs) { $exe = $vs.FullName }
        }

        if (-not $exe) {
            $best = Get-BestExe $gameFolderFull
            if ($best) { $exe = $best.FullName }
        }

        if ($exe -and (Test-Path $exe)) {
            $icoFromExe = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
            if ($icoFromExe) { return $icoFromExe.ToBitmap() }
        }
    } catch { }

    return $null
}

function Launch-GameByName($gameName) {
    $path = Join-Path $root $gameName
    if (!(Test-Path $path)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Dossier introuvable :`n$path",
            "Erreur",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    if ($gameName -match "^Vintage Story") {
        $vs = Get-VintageStoryExe $path
        if ($vs) {
            $status.Text = "Lancement: $($vs.Name)"
            Start-GameSafe $vs.FullName $vs.DirectoryName $gameName
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Vintage Story: exe introuvable dans :`n$path",
                "Erreur",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        return
    }

    $exe = Get-BestExe $path
    if ($exe) {
        $status.Text = "Lancement: $($exe.Name)"
        Start-GameSafe $exe.FullName $exe.DirectoryName $gameName
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Aucun .exe valide trouve dans :`n$path",
            "Erreur",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
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

# Double buffering (anti flicker)
try { $form.GetType().GetProperty("DoubleBuffered","NonPublic,Instance").SetValue($form,$true,$null) } catch { }

$launcherIco = Join-Path $root "MonkeyD_Launcher.ico"
if (Test-Path $launcherIco) { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($launcherIco) }

$bg = Join-Path $root "MonkeyDLauncher_BG.png"
if (Test-Path $bg) {
    $form.BackgroundImage = [System.Drawing.Image]::FromFile($bg)
    $form.BackgroundImageLayout = "Stretch"
}

$status = New-Object System.Windows.Forms.Label
$status.Text = "Pret."
$status.ForeColor = [System.Drawing.Color]::White
$status.BackColor = [System.Drawing.Color]::Transparent
$status.AutoSize = $true
$form.Controls.Add($status)

# --------- CAROUSEL (1 jeu affiché) ---------
$folders = @(Get-GamesFolders | Sort-Object Name)

$tileSize = 170
$cardH    = $tileSize
$overlayAlpha = 25

$script:tileX = 0
$script:tileY = 0
$script:currentIndex = 0

$card = New-Object System.Windows.Forms.Panel
$card.Size = New-Object System.Drawing.Size($tileSize, $cardH)
$card.BackColor = [System.Drawing.Color]::Transparent
$card.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($card)

# Double buffering panel
try { $card.GetType().GetProperty("DoubleBuffered","NonPublic,Instance").SetValue($card,$true,$null) } catch { }

$card.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($overlayAlpha, 0, 0, 0))
    $g.FillRectangle($brush, 0, 0, ($tileSize-1), ($tileSize-1))
    $brush.Dispose()

    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200,180,140), 2)
    $g.DrawRectangle($pen, 0, 0, ($tileSize-1), ($tileSize-1))
    $pen.Dispose()
})

$pic = New-Object System.Windows.Forms.PictureBox
$pic.Size = New-Object System.Drawing.Size($tileSize, $tileSize)
$pic.Location = New-Object System.Drawing.Point(0, 0)
$pic.SizeMode = "Zoom"
$pic.Padding = New-Object System.Windows.Forms.Padding(22)
$pic.BackColor = [System.Drawing.Color]::Transparent
$pic.Cursor = [System.Windows.Forms.Cursors]::Hand
$card.Controls.Add($pic)

$nameLbl = New-Object System.Windows.Forms.Label
$nameLbl.Size = New-Object System.Drawing.Size(($tileSize + 140), 44)
$nameLbl.TextAlign = "MiddleCenter"
$nameLbl.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 210, 160)
$nameLbl.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$nameLbl.BackColor = [System.Drawing.Color]::Transparent
$nameLbl.AutoEllipsis = $true
$nameLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($nameLbl)

$btnL = New-Object System.Windows.Forms.Button
$btnL.Text = "<"
$btnL.Size = New-Object System.Drawing.Size(55, 55)
$btnL.FlatStyle = "Flat"
$btnL.FlatAppearance.BorderSize = 1
$btnL.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200,180,140)
$btnL.BackColor = [System.Drawing.Color]::FromArgb(70, 0, 0, 0)
$btnL.ForeColor = [System.Drawing.Color]::FromArgb(235,210,160)
$btnL.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$btnL.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnL)

$btnR = New-Object System.Windows.Forms.Button
$btnR.Text = ">"
$btnR.Size = New-Object System.Drawing.Size(55, 55)
$btnR.FlatStyle = "Flat"
$btnR.FlatAppearance.BorderSize = 1
$btnR.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200,180,140)
$btnR.BackColor = [System.Drawing.Color]::FromArgb(70, 0, 0, 0)
$btnR.ForeColor = [System.Drawing.Color]::FromArgb(235,210,160)
$btnR.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$btnR.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnR)

function Reposition-Carousel {
    $script:tileX = [int](($form.ClientSize.Width  - $tileSize) / 2)
    $script:tileY = [int](($form.ClientSize.Height - $tileSize) / 2) + 70

    if ($script:tileX -lt 10) { $script:tileX = 10 }
    if ($script:tileY -lt 10) { $script:tileY = 10 }

    $card.Location = New-Object System.Drawing.Point($script:tileX, $script:tileY)
    $nameLbl.Location = New-Object System.Drawing.Point(($script:tileX - 70), ($script:tileY + $tileSize + 10))

    $btnL.Location = New-Object System.Drawing.Point(($script:tileX - 70), ($script:tileY + [int]($tileSize/2) - 25))
    $btnR.Location = New-Object System.Drawing.Point(($script:tileX + $tileSize + 15), ($script:tileY + [int]($tileSize/2) - 25))

    $card.BringToFront()
    $btnL.BringToFront()
    $btnR.BringToFront()
    $nameLbl.BringToFront()
}

function Set-CardContent($idx) {
    if ($folders.Count -eq 0) {
        $nameLbl.Text = "Aucun jeu detecte"
        $status.Text  = "Jeux detectes: 0"
        if ($pic.Image) { $pic.Image.Dispose(); $pic.Image = $null }
        return
    }

    $g = $folders[$idx]
    $nameLbl.Text = $g.Name

    if ($pic.Image) { $pic.Image.Dispose(); $pic.Image = $null }
    $img = Get-GameImage $g.FullName
    if ($img) { $pic.Image = $img }

    $status.Text = "Pret. (" + ($idx+1) + "/" + $folders.Count + ")"
}

# --------- ANIMATION FLUIDE (corrigée) ---------
# Plus fluide = pas trop long, pas trop violent, easing des 2 côtés
$script:animTimer = New-Object System.Windows.Forms.Timer
$script:animTimer.Interval = 15   # stable, fluide
$script:animStep = 0
$script:animDir = 0
$script:pendingIndex = 0
$script:phase = 0
$script:baseX = 0

# réglages anim
$script:animMaxSteps = 5   # 12-16 = bien
$script:animOffset   = 3   # slide court (pas un taxi)
$script:animTimer.Interval = 3

function Ease-InOut($t) {
    # t entre 0 et 1
    return (0.5 - ([math]::Cos($t * [math]::PI) / 2))
}

function Animate-ToIndex($newIndex, $dir) {
    if ($folders.Count -eq 0) { return }
    if ($script:animTimer.Enabled) { return }

    $script:pendingIndex = $newIndex
    $script:animDir = $dir
    $script:phase = 0
    $script:animStep = 0
    $script:baseX = $script:tileX
    $script:animTimer.Start()
}

$script:animTimer.Add_Tick({
    $max = $script:animMaxSteps
    $off = $script:animOffset

    if ($script:phase -eq 0) {
        # PHASE 0 = sort doucement jusqu'à offset
        $script:animStep++
        $t = $script:animStep / $max
        if ($t -gt 1) { $t = 1 }
        $ease = Ease-InOut $t
        $dx = [int](($script:animDir * $off) * $ease)

        $card.Left = $script:baseX + $dx
        $nameLbl.Left = ($script:baseX - 70) + $dx

        if ($script:animStep -ge $max) {
            Set-CardContent $script:pendingIndex
            $script:phase = 1
            $script:animStep = 0
        }
    }
    else {
        # PHASE 1 = revient doucement de offset -> 0
        $script:animStep++
        $t = $script:animStep / $max
        if ($t -gt 1) { $t = 1 }
        $ease = Ease-InOut $t
        $dx = [int](($script:animDir * $off) * (1 - $ease))

        $card.Left = $script:baseX + $dx
        $nameLbl.Left = ($script:baseX - 70) + $dx

        if ($script:animStep -ge $max) {
            $card.Left = $script:baseX
            $nameLbl.Left = ($script:baseX - 70)
            $script:animTimer.Stop()
        }
    }
})

function Prev-Game {
    if ($folders.Count -eq 0) { return }
    $new = $script:currentIndex - 1
    if ($new -lt 0) { $new = $folders.Count - 1 }
    $script:currentIndex = $new
    Animate-ToIndex $new -1
}

function Next-Game {
    if ($folders.Count -eq 0) { return }
    $new = $script:currentIndex + 1
    if ($new -ge $folders.Count) { $new = 0 }
    $script:currentIndex = $new
    Animate-ToIndex $new 1
}

$btnL.Add_Click({ Prev-Game })
$btnR.Add_Click({ Next-Game })

$card.Add_Click({ if ($folders.Count -gt 0) { Launch-GameByName $folders[$script:currentIndex].Name } })
$pic.Add_Click({  if ($folders.Count -gt 0) { Launch-GameByName $folders[$script:currentIndex].Name } })
$nameLbl.Add_Click({ if ($folders.Count -gt 0) { Launch-GameByName $folders[$script:currentIndex].Name } })

$form.Add_MouseWheel({
    param($sender, $e)
    if ($e.Delta -gt 0) { Prev-Game } else { Next-Game }
})

$form.KeyPreview = $true
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Left)  { Prev-Game }
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Right) { Next-Game }
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        if ($folders.Count -gt 0) { Launch-GameByName $folders[$script:currentIndex].Name }
    }
})

$form.Add_Shown({
    Reposition-Carousel
    if ($folders.Count -gt 0) { Set-CardContent 0 } else { Set-CardContent 0 }

    $status.Text = "Jeux detectes: " + $folders.Count
    $h = [int]$form.ClientSize.Height
    $status.Location = New-Object System.Drawing.Point(20, ($h - 30))
})

[void]$form.ShowDialog()
