[CmdletBinding()]
param(
    # Shown in Windows' "Installed apps" list. The one-file setup passes its own version.
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$platform = [System.Environment]::OSVersion.Platform
if ($platform -ne [System.PlatformID]::Win32NT) {
    throw 'Terminal Board only supports Windows.'
}

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    throw 'Windows Terminal (wt.exe) was not found. Install Windows Terminal first.'
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
# Windows' "Installed apps" list runs this copy when the user chooses Uninstall.
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination $installDirectory -Force
# The hotkey script was replaced by the clipboard helper, and the settings screen now lives
# inside the helper exe; drop the copies an older install left behind.
Remove-Item -LiteralPath (Join-Path $moduleDirectory 'Invoke-TbImageHotkey.ps1') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $moduleDirectory 'TbDesk.ps1') -Force -ErrorAction SilentlyContinue

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
        Write-Warning "Not overwriting an existing command: $shimPath"
    }
}

# The installed module knows where the helper lives and how to draw the icon, so use it
# instead of repeating that here.
Import-Module (Join-Path $moduleDirectory 'TerminalBoard.psm1') -Force

$iconPath = Join-Path $installDirectory 'TerminalBoard.ico'

# A running helper may still hold the old icon file open, so stop it before drawing a new one.
try {
    Stop-TbClipHelper
}
catch {
    Write-Warning "Could not stop the previous helper: $($_.Exception.Message)"
}

try {
    New-TbIcon -Path $iconPath
}
catch {
    Write-Warning "Could not draw the icon: $($_.Exception.Message)"
    # An icon from an earlier install is just as good; only go without when there is none.
    if (-not (Test-Path -LiteralPath $iconPath)) {
        $iconPath = $null
    }
}

try {
    Stop-TbClipHelper
    New-TbClipboardHelper `
        -SourcePath (Join-Path $PSScriptRoot 'src\TbClipboardHelper.cs'), (Join-Path $PSScriptRoot 'src\TbDeskWindow.cs') `
        -XamlPath (Join-Path $PSScriptRoot 'src\TbDesk.xaml') `
        -OutputPath (Get-TbClipHelperPath) `
        -IconPath $iconPath
    Set-TbClipAutostart -Enabled $true
    Start-TbClipHelper
    Write-Host 'Screenshot helper is on: take a screenshot (Win+Shift+S), then Ctrl+V in the terminal.'
}
catch {
    Write-Warning "Could not install the screenshot helper: $($_.Exception.Message)"
    Write-Warning 'You can still use Alt+V in Claude Code, or the tb img command.'
}

try {
    $startMenuDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Terminal Board'
    New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null

    $wtPath = (Get-Command wt.exe).Source
    $wshShell = New-Object -ComObject WScript.Shell

    # The Ctrl+Alt+C capture shortcut was replaced by the clipboard helper. Clear its
    # hotkey first so Explorer lets go of the key combination, then delete it. The quick-open
    # shortcut was renamed ("Mo nhanh" -> "Quick Open"), so the old one goes here too.
    $legacyHotkeyShortcuts = @(
        (Join-Path $startMenuDirectory 'Terminal Board - Capture Image.lnk'),
        (Join-Path $startMenuDirectory 'Terminal Board - Mo nhanh.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Terminal Board - Capture Image.lnk')
    )
    foreach ($legacyHotkeyShortcut in $legacyHotkeyShortcuts) {
        if (Test-Path -LiteralPath $legacyHotkeyShortcut) {
            $legacy = $wshShell.CreateShortcut($legacyHotkeyShortcut)
            $legacy.Hotkey = ''
            $legacy.Save()
            Remove-Item -LiteralPath $legacyHotkeyShortcut -Force
        }
    }

    # The main entry point: the settings screen, where the user picks how many panes there are and
    # what each one runs, then opens the board. It lives in the helper exe, which keeps the screen
    # ready in the background, so these icons open it almost instantly.
    $helperExe = Get-TbClipHelperPath
    if (Test-Path -LiteralPath $helperExe) {
        $deskDescription = 'Choose the number of terminal panes and the agent in each (Claude, Codex, Antigravity...), then open the workspace'

        $boardShortcut = $wshShell.CreateShortcut((Join-Path $startMenuDirectory 'Terminal Board.lnk'))
        $boardShortcut.TargetPath = $helperExe
        $boardShortcut.Arguments = '--desk'
        $boardShortcut.WorkingDirectory = $installDirectory
        $boardShortcut.Description = $deskDescription
        if ($iconPath) { $boardShortcut.IconLocation = $iconPath }
        $boardShortcut.Save()

        # Same screen, one icon on the Desktop so the working window is always easy to call up.
        $desktopShortcut = $wshShell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Terminal Board.lnk'))
        $desktopShortcut.TargetPath = $helperExe
        $desktopShortcut.Arguments = '--desk'
        $desktopShortcut.WorkingDirectory = $installDirectory
        $desktopShortcut.Description = $deskDescription
        if ($iconPath) { $desktopShortcut.IconLocation = $iconPath }
        $desktopShortcut.Save()

        $quickShortcut = $wshShell.CreateShortcut((Join-Path $startMenuDirectory 'Terminal Board - Quick Open.lnk'))
        $quickShortcut.TargetPath = $helperExe
        $quickShortcut.Arguments = '--open'
        $quickShortcut.WorkingDirectory = $installDirectory
        $quickShortcut.Description = 'Open the workspace you saved last time, without asking again'
        if ($iconPath) { $quickShortcut.IconLocation = $iconPath }
        $quickShortcut.Save()
    }
    else {
        Write-Warning 'No settings-screen icon was created because the helper could not be built. You can still use: tb 5, tb agents.'
    }

    $agentsShortcut = $wshShell.CreateShortcut((Join-Path $startMenuDirectory 'Terminal Board - Agents.lnk'))
    # tb agents opens its own maximized window, so the launcher stays hidden. Running it
    # inside a Terminal pane would leave that pane behind as a stray extra window.
    $agentsShortcut.TargetPath = (Get-Command powershell.exe).Source
    $agentsShortcut.Arguments = '-NoLogo -NoProfile -WindowStyle Hidden -Command "tb agents"'
    $agentsShortcut.WindowStyle = 7
    $agentsShortcut.WorkingDirectory = $env:USERPROFILE
    $agentsShortcut.Description = 'Open your AI agents side by side (create the profile first: tb profile set agents ...)'
    if ($iconPath) { $agentsShortcut.IconLocation = $iconPath }
    $agentsShortcut.Save()

    Write-Host "Created Start Menu shortcuts: Terminal Board"
}
catch {
    Write-Warning "Could not create the Start Menu shortcuts: $($_.Exception.Message)"
}

# Register with Windows so Terminal Board shows up in "Installed apps" and can be removed from there.
try {
    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TerminalBoard'
    New-Item -Path $uninstallKey -Force | Out-Null
    $uninstallScript = Join-Path $installDirectory 'uninstall.ps1'
    $uninstallEntries = [ordered]@{
        DisplayName     = 'Terminal Board'
        InstallLocation = $installDirectory
        UninstallString = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$uninstallScript`" -Pause"
        NoModify        = 1
        NoRepair        = 1
    }
    if ($iconPath) { $uninstallEntries['DisplayIcon'] = $iconPath }
    if ($Version) { $uninstallEntries['DisplayVersion'] = $Version }
    foreach ($entryName in $uninstallEntries.Keys) {
        $entryType = if ($uninstallEntries[$entryName] -is [int]) { 'DWord' } else { 'String' }
        New-ItemProperty -Path $uninstallKey -Name $entryName -Value $uninstallEntries[$entryName] -PropertyType $entryType -Force | Out-Null
    }
}
catch {
    Write-Warning "Could not add Terminal Board to the installed apps list: $($_.Exception.Message)"
}

Write-Host "Installed Terminal Board to: $installDirectory"
Write-Host 'Click the Terminal Board icon on the Desktop to choose the panes and agents, then open the workspace.'
Write-Host 'Or type: tb ui (settings screen), tb desk (open the saved workspace), tb 5 (split into 5 panes).'
