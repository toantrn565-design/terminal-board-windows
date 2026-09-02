[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$windowsAppsDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
$installDirectory = Join-Path $windowsAppsDirectory 'TerminalBoard'
$legacyInstallDirectory = Join-Path $env:LOCALAPPDATA 'TerminalBoard\bin'
$terminalBoardDataDirectory = Join-Path $env:LOCALAPPDATA 'TerminalBoard'
$shimPath = Join-Path $windowsAppsDirectory 'tb.cmd'

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$updatedParts = @(
    $userPath -split ';' |
        Where-Object { $_ -and $_.TrimEnd('\') -ine $legacyInstallDirectory.TrimEnd('\') }
)
[Environment]::SetEnvironmentVariable('Path', ($updatedParts -join ';'), 'User')

if (Test-Path -LiteralPath $installDirectory) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
}

if (Test-Path -LiteralPath $terminalBoardDataDirectory) {
    Remove-Item -LiteralPath $terminalBoardDataDirectory -Recurse -Force
}

if (Test-Path -LiteralPath $shimPath) {
    $shimContents = Get-Content -LiteralPath $shimPath -Raw -ErrorAction SilentlyContinue
    if ($shimContents -match 'Terminal Board shim') {
        Remove-Item -LiteralPath $shimPath -Force
    }
}

Write-Host 'Da go Terminal Board. Hay mo terminal moi de cap nhat PATH.'
