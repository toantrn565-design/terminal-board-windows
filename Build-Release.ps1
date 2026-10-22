[CmdletBinding()]
param(
    # Shown in the setup window, in the file's properties and in Windows' "Installed apps" list.
    [string]$Version = '1.0.0',

    # Where the kit, the zip and the setup file are written. The tests point this at a temp folder.
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must look like 1.0.0, not '$Version'."
}

$distDirectory = $OutputDirectory
$stagingDirectory = Join-Path $distDirectory 'TerminalBoard'
$zipPath = Join-Path $distDirectory 'TerminalBoard.zip'
$setupPath = Join-Path $distDirectory 'TerminalBoardSetup.exe'

New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null
if (Test-Path -LiteralPath $stagingDirectory) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}
foreach ($oldFile in $zipPath, $setupPath) {
    if (Test-Path -LiteralPath $oldFile) {
        Remove-Item -LiteralPath $oldFile -Force
    }
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
    'TbClipboardHelper.cs',
    'TbDeskWindow.cs',
    'TbDesk.xaml'
)

foreach ($file in $rootFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $stagingDirectory -Force
}
$sourceSrcDirectory = Join-Path $PSScriptRoot 'src'
$stagingSrcDirectory = Join-Path $stagingDirectory 'src'
foreach ($file in $srcFiles) {
    Copy-Item -LiteralPath (Join-Path $sourceSrcDirectory $file) -Destination $stagingSrcDirectory -Force
}

# The kit ships its own icon so a shortcut to setup.cmd can carry it.
Import-Module (Join-Path $PSScriptRoot 'src\TerminalBoard.psm1') -Force
$iconPath = Join-Path $stagingDirectory 'TerminalBoard.ico'
New-TbIcon -Path $iconPath

# The zip is written here rather than with Compress-Archive, which (in Windows PowerShell 5.1)
# stores folders with backslashes that other unzip tools do not understand.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stagingRoot = (Resolve-Path -LiteralPath $stagingDirectory).Path.TrimEnd('\')
$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($stagedFile in Get-ChildItem -LiteralPath $stagingRoot -Recurse -File) {
        $entryName = $stagedFile.FullName.Substring($stagingRoot.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $stagedFile.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
    }
}
finally {
    $archive.Dispose()
}

# The one-file setup: a small program with the zip inside it. Built with the csc.exe that
# ships with Windows, like the helper, so no extra tools are needed.
$frameworkDirectory = $null
foreach ($candidate in "$env:windir\Microsoft.NET\Framework64\v4.0.30319", "$env:windir\Microsoft.NET\Framework\v4.0.30319") {
    if (Test-Path -LiteralPath (Join-Path $candidate 'csc.exe')) {
        $frameworkDirectory = $candidate
        break
    }
}
if (-not $frameworkDirectory) {
    throw 'csc.exe (.NET Framework) was not found, so the setup file cannot be built.'
}

$assemblyInfoPath = Join-Path $distDirectory 'TbSetupAssemblyInfo.cs'
$fourPartVersion = "$Version.0"
@"
using System.Reflection;
[assembly: AssemblyTitle("Terminal Board Setup")]
[assembly: AssemblyProduct("Terminal Board")]
[assembly: AssemblyDescription("Installs Terminal Board for the current Windows user")]
[assembly: AssemblyVersion("$fourPartVersion")]
[assembly: AssemblyFileVersion("$fourPartVersion")]
[assembly: AssemblyInformationalVersion("$Version")]
"@ | Set-Content -LiteralPath $assemblyInfoPath -Encoding ASCII

$setupDirectory = Join-Path $PSScriptRoot 'setup'
$compilerArguments = @(
    '/nologo', '/target:winexe', '/optimize+', '/codepage:65001', "/out:$setupPath",
    "/win32icon:$iconPath", "/win32manifest:$(Join-Path $setupDirectory 'TbSetup.manifest')",
    '/reference:System.dll', '/reference:System.Core.dll', '/reference:System.Xaml.dll',
    '/reference:System.IO.Compression.dll', '/reference:System.IO.Compression.FileSystem.dll'
)
foreach ($wpfLibrary in 'PresentationFramework', 'PresentationCore', 'WindowsBase') {
    $compilerArguments += "/reference:$(Join-Path $frameworkDirectory "WPF\$wpfLibrary.dll")"
}
$compilerArguments += "/resource:$zipPath,payload.zip"
$compilerArguments += "/resource:$iconPath,logo.ico"
$compilerArguments += (Join-Path $setupDirectory 'TbSetup.cs')
$compilerArguments += $assemblyInfoPath

$global:LASTEXITCODE = 0
$compilerOutput = & (Join-Path $frameworkDirectory 'csc.exe') @compilerArguments
$compilerExitCode = $LASTEXITCODE
Remove-Item -LiteralPath $assemblyInfoPath -Force -ErrorAction SilentlyContinue
if ($compilerExitCode -ne 0 -or -not (Test-Path -LiteralPath $setupPath)) {
    throw "Building the setup file failed:`n$($compilerOutput -join "`n")"
}

Write-Host "Packaged: $stagingDirectory"
Write-Host "Zipped: $zipPath"
Write-Host "Setup file: $setupPath ($([math]::Round((Get-Item -LiteralPath $setupPath).Length / 1KB)) KB, version $Version)"
