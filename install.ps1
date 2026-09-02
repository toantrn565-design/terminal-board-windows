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

Write-Host "Da cai Terminal Board vao: $installDirectory"
Write-Host 'Su dung: tb 5'
