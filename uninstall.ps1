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

# Stop the clipboard helper first: a running exe cannot be deleted, and asking it
# to quit lets its tray icon disappear cleanly.
$helperPath = Join-Path $installDirectory 'TbClipboardHelper.exe'
if (Test-Path -LiteralPath $helperPath) {
    Start-Process -FilePath $helperPath -ArgumentList '--exit' -Wait
    $runningHelpers = @(Get-Process -Name 'TbClipboardHelper' -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $helperPath })
    foreach ($runningHelper in $runningHelpers) {
        if (-not $runningHelper.WaitForExit(3000)) {
            $runningHelper.Kill()
        }
    }
}

$clipboardStartupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'Terminal Board Clipboard.lnk'
if (Test-Path -LiteralPath $clipboardStartupShortcut) {
    Remove-Item -LiteralPath $clipboardStartupShortcut -Force
}

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

$startMenuDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Terminal Board'
if (Test-Path -LiteralPath $startMenuDirectory) {
    Remove-Item -LiteralPath $startMenuDirectory -Recurse -Force
}

$desktopHotkeyShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Terminal Board - Capture Image.lnk'
if (Test-Path -LiteralPath $desktopHotkeyShortcut) {
    Remove-Item -LiteralPath $desktopHotkeyShortcut -Force
}

$desktopBoardShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Terminal Board.lnk'
if (Test-Path -LiteralPath $desktopBoardShortcut) {
    $desktopBoardLink = (New-Object -ComObject WScript.Shell).CreateShortcut($desktopBoardShortcut)
    # Ours if it opens the helper exe (current) or the old PowerShell settings screen.
    if ($desktopBoardLink.TargetPath -match 'TbClipboardHelper\.exe' -or $desktopBoardLink.Arguments -match 'TbDesk\.ps1') {
        Remove-Item -LiteralPath $desktopBoardShortcut -Force
    }
}

Write-Host 'Terminal Board was removed. Open a new terminal to refresh PATH.'
