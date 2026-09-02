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

$installDirectory = Join-Path $env:LOCALAPPDATA 'TerminalBoard\bin'
$moduleDirectory = Join-Path $installDirectory 'src'
$windowsAppsDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
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

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathParts = @($userPath -split ';' | Where-Object { $_ })
$alreadyOnPath = $pathParts | Where-Object { $_.TrimEnd('\') -ieq $installDirectory.TrimEnd('\') }

if (-not $alreadyOnPath) {
    $updatedPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
        $installDirectory
    }
    else {
        $userPath.TrimEnd(';') + ';' + $installDirectory
    }
    [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
}

Write-Host "Da cai Terminal Board vao: $installDirectory"
Write-Host 'Su dung: tb 5'
