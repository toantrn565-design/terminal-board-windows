[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installDirectory = Join-Path $env:LOCALAPPDATA 'TerminalBoard\bin'
$terminalBoardDirectory = Split-Path -Parent $installDirectory
$shimPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\tb.cmd'

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$updatedParts = @(
    $userPath -split ';' |
        Where-Object { $_ -and $_.TrimEnd('\') -ine $installDirectory.TrimEnd('\') }
)
[Environment]::SetEnvironmentVariable('Path', ($updatedParts -join ';'), 'User')

if (Test-Path -LiteralPath $terminalBoardDirectory) {
    Remove-Item -LiteralPath $terminalBoardDirectory -Recurse -Force
}

if (Test-Path -LiteralPath $shimPath) {
    $shimContents = Get-Content -LiteralPath $shimPath -Raw -ErrorAction SilentlyContinue
    if ($shimContents -match 'Terminal Board shim') {
        Remove-Item -LiteralPath $shimPath -Force
    }
}

Write-Host 'Da go Terminal Board. Hay mo terminal moi de cap nhat PATH.'
