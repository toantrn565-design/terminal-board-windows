[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$platform = [System.Environment]::OSVersion.Platform
if ($platform -ne [System.PlatformID]::Win32NT) {
    throw 'Terminal Board chi ho tro Windows.'
}

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    throw 'Khong tim thay Windows Terminal (wt.exe). Hay cai Windows Terminal truoc.'
}

$windowsAppsDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
$installDirectory = Join-Path $windowsAppsDirectory 'TerminalBoard'
$moduleDirectory = Join-Path $installDirectory 'src'
$shimPath = Join-Path $windowsAppsDirectory 'tb.cmd'

New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tb.ps1') -Destination $installDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tb.cmd') -Destination $installDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src\TerminalBoard.psm1') -Destination $moduleDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src\Save-TbClipboardImageWorker.ps1') -Destination $moduleDirectory -Force

if (Test-Path -LiteralPath $windowsAppsDirectory) {
    $canInstallShim = -not (Test-Path -LiteralPath $shimPath)
    if (-not $canInstallShim) {
        $existingShim = Get-Content -LiteralPath $shimPath -Raw -ErrorAction SilentlyContinue
        $canInstallShim = $existingShim -match 'Terminal Board shim'
    }

    if ($canInstallShim) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tb-shim.cmd') -Destination $shimPath -Force
    }
    else {
        Write-Warning "Khong ghi de lenh da ton tai: $shimPath"
    }
}

function New-TbIcon {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Add-Type -AssemblyName System.Drawing

    $size = 256
    $bitmap = New-Object System.Drawing.Bitmap $size, $size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 24, 24, 36))
    $paneBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 60, 220, 160))
    $backgroundPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $cornerRadius = 40
    $diameter = $cornerRadius * 2
    $bounds = New-Object System.Drawing.Rectangle 0, 0, $size, $size

    $backgroundPath.AddArc($bounds.X, $bounds.Y, $diameter, $diameter, 180, 90)
    $backgroundPath.AddArc($bounds.Right - $diameter, $bounds.Y, $diameter, $diameter, 270, 90)
    $backgroundPath.AddArc($bounds.Right - $diameter, $bounds.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $backgroundPath.AddArc($bounds.X, $bounds.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $backgroundPath.CloseFigure()
    $graphics.FillPath($bgBrush, $backgroundPath)

    $margin = 30
    $gap = 14
    $paneCount = 5
    $paneWidth = ([double]($size - 2 * $margin - $gap * ($paneCount - 1))) / $paneCount
    $paneHeight = $size - 2 * $margin

    for ($i = 0; $i -lt $paneCount; $i++) {
        $x = $margin + $i * ($paneWidth + $gap)
        $graphics.FillRectangle($paneBrush, [float]$x, [float]$margin, [float]$paneWidth, [float]$paneHeight)
    }

    $iconHandle = $bitmap.GetHicon()
    try {
        $icon = [System.Drawing.Icon]::FromHandle($iconHandle)
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create)
        try {
            $icon.Save($stream)
        }
        finally {
            $stream.Close()
        }
        $icon.Dispose()
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        $bgBrush.Dispose()
        $paneBrush.Dispose()
        $backgroundPath.Dispose()
    }
}

$iconPath = Join-Path $installDirectory 'TerminalBoard.ico'
try {
    New-TbIcon -Path $iconPath
}
catch {
    Write-Warning "Khong tao duoc icon: $($_.Exception.Message)"
    $iconPath = $null
}

try {
    $startMenuDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Terminal Board'
    New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null

    $wtPath = (Get-Command wt.exe).Source
    $wshShell = New-Object -ComObject WScript.Shell

    $boardShortcut = $wshShell.CreateShortcut((Join-Path $startMenuDirectory 'Terminal Board.lnk'))
    $boardShortcut.TargetPath = $wtPath
    $boardShortcut.Arguments = 'powershell -NoExit -Command tb'
    $boardShortcut.WorkingDirectory = $env:USERPROFILE
    $boardShortcut.Description = 'Chia Windows Terminal thanh nhieu pane'
    if ($iconPath) { $boardShortcut.IconLocation = $iconPath }
    $boardShortcut.Save()

    $agentsShortcut = $wshShell.CreateShortcut((Join-Path $startMenuDirectory 'Terminal Board - Agents.lnk'))
    $agentsShortcut.TargetPath = $wtPath
    $agentsShortcut.Arguments = 'powershell -NoExit -Command "tb agents"'
    $agentsShortcut.WorkingDirectory = $env:USERPROFILE
    $agentsShortcut.Description = 'Mo cac AI agent trong nhieu pane (tao truoc bang: tb profile set agents ...)'
    if ($iconPath) { $agentsShortcut.IconLocation = $iconPath }
    $agentsShortcut.Save()

    Write-Host "Da tao shortcut trong Start Menu: Terminal Board"
}
catch {
    Write-Warning "Khong tao duoc shortcut Start Menu: $($_.Exception.Message)"
}

Write-Host "Da cai Terminal Board vao: $installDirectory"
Write-Host 'Su dung: tb 5'
