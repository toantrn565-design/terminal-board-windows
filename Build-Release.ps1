[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$distDirectory = Join-Path $PSScriptRoot 'dist'
$stagingDirectory = Join-Path $distDirectory 'TerminalBoard'
$zipPath = Join-Path $distDirectory 'TerminalBoard.zip'

if (Test-Path -LiteralPath $stagingDirectory) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingDirectory 'src') -Force | Out-Null

# Only the files install.ps1 / setup.cmd actually need at runtime - no git
# history, no tests, no dev tooling.
$rootFiles = @(
    'README.md',
    'SHORTCUTS.md',
    'install.ps1',
    'uninstall.ps1',
    'setup.cmd',
    'tb.ps1',
    'tb.cmd',
    'tb-shim.cmd'
)
$srcFiles = @(
    'TerminalBoard.psm1',
    'Save-TbClipboardImageWorker.ps1',
    'Invoke-TbImageHotkey.ps1'
)

foreach ($file in $rootFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $stagingDirectory -Force
}
$sourceSrcDirectory = Join-Path $PSScriptRoot 'src'
$stagingSrcDirectory = Join-Path $stagingDirectory 'src'
foreach ($file in $srcFiles) {
    Copy-Item -LiteralPath (Join-Path $sourceSrcDirectory $file) -Destination $stagingSrcDirectory -Force
}

Compress-Archive -Path (Join-Path $stagingDirectory '*') -DestinationPath $zipPath -Force

Write-Host "Da dong goi: $stagingDirectory"
Write-Host "Da nen: $zipPath"
