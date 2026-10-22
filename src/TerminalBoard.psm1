Set-StrictMode -Version Latest

$script:TbMinPaneCount = 1
$script:TbMaxPaneCount = 12

# Marks a pane that should be a plain terminal (just the shell, nothing launched in it).
$script:TbPlainShell = '@shell'

function Get-TbSettingsPath {
    $baseDirectory = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'TerminalBoard'
    }
    else {
        Join-Path $HOME '.terminal-board'
    }

    Join-Path $baseDirectory 'settings.json'
}

function Get-TbSettings {
    $defaults = [ordered]@{
        count  = 5
        layout = 'columns'
    }

    $settingsPath = Get-TbSettingsPath
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        return [pscustomobject]$defaults
    }

    try {
        $saved = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $savedCount = 0
        if (
            $null -ne $saved.count -and
            [int]::TryParse([string]$saved.count, [ref]$savedCount) -and
            $savedCount -ge $script:TbMinPaneCount -and
            $savedCount -le $script:TbMaxPaneCount
        ) {
            $defaults.count = $savedCount
        }
        if ($null -ne $saved.layout -and $saved.layout -in @('columns', 'rows')) {
            $defaults.layout = [string]$saved.layout
        }
    }
    catch {
        # A damaged settings file should never prevent the board from opening.
    }

    [pscustomobject]$defaults
}

function Save-TbSettings {
    param(
        [Parameter(Mandatory)]
        [int]$Count,

        [Parameter(Mandatory)]
        [ValidateSet('columns', 'rows')]
        [string]$Layout
    )

    $settingsPath = Get-TbSettingsPath
    $settingsDirectory = Split-Path -Parent $settingsPath
    New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null

    [ordered]@{
        count  = $Count
        layout = $Layout
    } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding utf8
}

function Assert-TbPaneCount {
    param(
        [Parameter(Mandatory)]
        [int]$Count
    )

    if ($Count -lt $script:TbMinPaneCount -or $Count -gt $script:TbMaxPaneCount) {
        throw "The number of panes must be between $script:TbMinPaneCount and $script:TbMaxPaneCount."
    }
}

function Get-TbSplitPlan {
    <#
        Windows Terminal focuses the newly-created pane. Each split therefore
        carves one final pane out of the active remainder. The fractions below
        make all resulting panes equal:
        5 panes -> .8, .75, .666667, .5.
    #>
    param(
        [Parameter(Mandatory)]
        [int]$Count,

        [ValidateSet('columns', 'rows')]
        [string]$Layout = 'columns'
    )

    Assert-TbPaneCount -Count $Count

    $orientation = if ($Layout -eq 'columns') { '-V' } else { '-H' }
    $plan = [System.Collections.Generic.List[object]]::new()

    for ($paneNumber = 2; $paneNumber -le $Count; $paneNumber++) {
        $remainingBeforeSplit = $Count - $paneNumber + 2
        $newPaneShare = ($remainingBeforeSplit - 1) / $remainingBeforeSplit

        $plan.Add([pscustomobject]@{
            PaneNumber  = $paneNumber
            Orientation = $orientation
            Size        = $newPaneShare
        })
    }

    $plan.ToArray()
}

function Get-TbShellExecutable {
    <#
        Profile panes run a specific command instead of duplicating the
        caller's shell, so they need a stable host. Prefer pwsh.exe (matches
        tb.cmd's own preference) and fall back to the Windows PowerShell that
        ships with every Windows install.
    #>
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }

    (Get-Command powershell.exe).Source
}

function ConvertTo-TbCommandArguments {
    <#
        Turns a saved profile command string (e.g. "npm run dev") into the
        argv Windows Terminal should run after "--", so the pane stays open
        (-NoExit) once the command finishes or is interrupted.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    if ($Command -eq $script:TbPlainShell) {
        return @((Get-TbShellExecutable), '-NoExit')
    }

    # Windows Terminal reads ';' as its own command separator even inside a
    # quoted argument, so it must be escaped for the pane to get the command whole.
    @((Get-TbShellExecutable), '-NoExit', '-Command', $Command.Replace(';', '\;'))
}

function Get-TbPaneTitle {
    <#
        The title Windows Terminal shows for a pane (the tab shows the focused pane's
        title, so this is how the user tells the agents apart).
    #>
    param(
        [string]$Command,

        [Parameter(Mandatory)]
        [int]$Number
    )

    if (-not $Command) {
        return "TB $Number"
    }

    $known = @{
        $script:TbPlainShell = 'Terminal'
        'claude'             = 'Claude Code'
        'codex'              = 'Codex'
        'agy'                = 'Antigravity'
    }
    $name = if ($known.ContainsKey($Command)) { $known[$Command] } elseif ($Command.Length -gt 24) { $Command.Substring(0, 24) } else { $Command }

    "$Number - $name"
}

function ConvertTo-TbSplitArguments {
    <#
        Arguments for a single split-pane operation. A pane that runs a command
        gets an explicit start directory instead of -D: Windows Terminal ignores
        the command when -D (duplicate the focused pane) is present and opens a
        plain shell instead.
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Split,

        [string]$Command,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('split-pane')
    $arguments.Add($Split.Orientation)
    $arguments.Add('-s')
    $arguments.Add($Split.Size.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture))
    if ($Command) {
        $arguments.Add('-d')
        $arguments.Add($WorkingDirectory)
    }
    else {
        $arguments.Add('-D')
    }
    $arguments.Add('--title')
    $arguments.Add((Get-TbPaneTitle -Command $Command -Number $Split.PaneNumber))
    $arguments.Add('--suppressApplicationTitle')

    if ($Command) {
        $arguments.Add('--')
        foreach ($token in (ConvertTo-TbCommandArguments -Command $Command)) {
            $arguments.Add($token)
        }
    }

    $arguments.ToArray()
}

function ConvertTo-TbWtArguments {
    param(
        [Parameter(Mandatory)]
        [int]$Count,

        [ValidateSet('columns', 'rows')]
        [string]$Layout = 'columns',

        [switch]$NewWindow,

        [string]$WorkingDirectory = (Get-Location).Path,

        [string[]]$Commands = @()
    )

    $arguments = [System.Collections.Generic.List[string]]::new()

    if ($NewWindow) {
        $arguments.Add('-w')
        $arguments.Add('new')
        # Maximized (not fullscreen): a board needs the room, but the taskbar must stay visible.
        $arguments.Add('-M')
        $arguments.Add('new-tab')
        $arguments.Add('-d')
        $arguments.Add($WorkingDirectory)
        $arguments.Add('--title')
        $firstCommand = if ($Commands.Count -ge 1) { $Commands[0] }
        $arguments.Add((Get-TbPaneTitle -Command $firstCommand -Number 1))
        $arguments.Add('--suppressApplicationTitle')
        if ($Commands.Count -ge 1 -and $Commands[0]) {
            $arguments.Add('--')
            foreach ($token in (ConvertTo-TbCommandArguments -Command $Commands[0])) {
                $arguments.Add($token)
            }
        }
    }
    else {
        $arguments.Add('-w')
        $arguments.Add('0')
    }

    $hasPreviousCommand = [bool]$NewWindow
    foreach ($split in (Get-TbSplitPlan -Count $Count -Layout $Layout)) {
        if ($hasPreviousCommand) {
            $arguments.Add(';')
        }
        $paneCommand = if ($Commands.Count -ge $split.PaneNumber) { $Commands[$split.PaneNumber - 1] }
        foreach ($token in (ConvertTo-TbSplitArguments -Split $split -Command $paneCommand -WorkingDirectory $WorkingDirectory)) {
            $arguments.Add($token)
        }
        $hasPreviousCommand = $true
    }

    if ($Count -gt 1) {
        $arguments.Add(';')
        $arguments.Add('move-focus')
        $arguments.Add('first')
    }

    $arguments.ToArray()
}

function Format-TbCommandPreview {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $formatted = foreach ($argument in $Arguments) {
        if ($argument -eq ';') {
            ';'
        }
        elseif ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '\"') + '"'
        }
        else {
            $argument
        }
    }

    'wt.exe ' + ($formatted -join ' ')
}

function Write-TbLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        $logPath = Join-Path (Split-Path -Parent (Get-TbSettingsPath)) 'tb.log'
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        Add-Content -LiteralPath $logPath -Value "[$timestamp] $Message" -Encoding utf8
    }
    catch {
        # Logging must not prevent pane creation.
    }
}

function Invoke-TbWtCommand {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ApplicationInfo]$Wt,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    Write-TbLog -Message (Format-TbCommandPreview -Arguments $Arguments)
    # A wt.exe call that opens a new window never sets $LASTEXITCODE, and reading
    # an unset variable throws under StrictMode (tb used to stop after the first
    # tab). Start from 0 so a launch that reports nothing counts as success.
    $global:LASTEXITCODE = 0
    & $Wt.Source @Arguments
    $exitCode = $LASTEXITCODE
    Write-TbLog -Message "exit=$exitCode"

    if ($exitCode -ne 0) {
        throw "Windows Terminal returned error code $exitCode."
    }
}

function Invoke-TerminalBoard {
    param(
        [Parameter(Mandatory)]
        [int]$Count,

        [ValidateSet('columns', 'rows')]
        [string]$Layout = 'columns',

        [switch]$DryRun,

        [switch]$NoRemember,

        [switch]$NewWindow,

        [string[]]$Commands = @()
    )

    Assert-TbPaneCount -Count $Count

    if ($Commands.Count -gt 0 -and $Commands.Count -ne $Count) {
        throw 'The number of commands in a profile must match the number of panes.'
    }

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Terminal Board only supports Windows.'
    }

    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $wt -and -not $DryRun) {
        throw 'Windows Terminal (wt.exe) was not found. Install Windows Terminal first.'
    }

    # A profile assigns a command to pane 1 too, which only a fresh window
    # can accept - the pane already running the current shell cannot be
    # redirected into a different process.
    $openNewWindow = $NewWindow -or -not [bool]$env:WT_SESSION -or $Commands.Count -gt 0

    if ($Count -eq 1 -and -not $openNewWindow) {
        if ($DryRun) {
            return 'Nothing to split: the current pane is already a single terminal.'
        }

        if (-not $NoRemember) {
            Save-TbSettings -Count $Count -Layout $Layout
        }
        try {
            $Host.UI.RawUI.WindowTitle = 'TB 1'
        }
        catch {
            # Some terminal hosts do not allow changing the application title.
        }
        return
    }

    if ($DryRun) {
        $arguments = ConvertTo-TbWtArguments -Count $Count -Layout $Layout -NewWindow:$openNewWindow -Commands $Commands
        return Format-TbCommandPreview -Arguments $arguments
    }

    if (-not $NoRemember) {
        Save-TbSettings -Count $Count -Layout $Layout
    }

    if (-not $openNewWindow) {
        try {
            $Host.UI.RawUI.WindowTitle = 'TB 1'
        }
        catch {
            # Some terminal hosts do not allow changing the application title.
        }
    }

    if ($openNewWindow) {
        # One wt.exe call that carries every step (new tab, splits, focus). Windows Terminal runs
        # them in order inside the new window. Separate calls can overtake the window's first tab
        # and land in a second tab, which is what used to happen on a slow start-up.
        $newWindowArguments = ConvertTo-TbWtArguments -Count $Count -Layout $Layout -NewWindow -Commands $Commands
        Invoke-TbWtCommand -Wt $wt -Arguments $newWindowArguments
        return
    }

    # The current window already exists, so each step can safely be its own call.
    foreach ($split in (Get-TbSplitPlan -Count $Count -Layout $Layout)) {
        $paneCommand = if ($Commands.Count -ge $split.PaneNumber) { $Commands[$split.PaneNumber - 1] }
        $splitArguments = @('-w', '0') + @(ConvertTo-TbSplitArguments -Split $split -Command $paneCommand -WorkingDirectory (Get-Location).Path)
        Invoke-TbWtCommand -Wt $wt -Arguments $splitArguments
        Start-Sleep -Milliseconds 100
    }

    if ($Count -gt 1) {
        Invoke-TbWtCommand -Wt $wt -Arguments @('-w', '0', 'move-focus', 'first')
    }
}

function Get-TbImageDirectory {
    Join-Path (Split-Path -Parent (Get-TbSettingsPath)) 'images'
}

function Save-TbClipboardImage {
    <#
        Reading/writing the clipboard requires an STA thread, but pwsh.exe
        (tb.cmd's preferred host) defaults to MTA. Rather than depend on the
        caller's apartment state, do the clipboard work in a disposable
        powershell.exe -Sta child process every time.
    #>
    [CmdletBinding()]
    param()

    $directory = Get-TbImageDirectory
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $fileName = 'img-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.png'
    $path = Join-Path $directory $fileName

    $workerPath = Join-Path $PSScriptRoot 'Save-TbClipboardImageWorker.ps1'
    if (-not (Test-Path -LiteralPath $workerPath)) {
        throw "Could not find the clipboard reader script: $workerPath"
    }

    $powershellExe = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $powershellExe) {
        throw 'Could not find powershell.exe to read the clipboard.'
    }

    & $powershellExe.Source -NoLogo -NoProfile -Sta -File $workerPath -Path $path
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 2) {
        throw 'There is no picture on the clipboard. Take a screenshot (Win+Shift+S) or copy a picture, then try again.'
    }
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $path)) {
        throw 'Could not read a picture from the clipboard.'
    }

    $path
}

function New-TbIcon {
    <#
        Draws the Terminal Board icon (five green panes on a dark rounded square)
        and saves it as an .ico file. Used for the Start Menu shortcuts, the tray
        icon and the setup shortcut.
    #>
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

function New-TbClipboardHelper {
    <#
        Compiles the clipboard helper with the csc.exe that ships with Windows
        (.NET Framework), so nothing extra has to be installed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SourcePath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$IconPath,

        # The settings screen layout, embedded in the exe.
        [string]$XamlPath
    )

    $csc = Join-Path ([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) {
        throw 'csc.exe (.NET Framework) was not found, so the screenshot helper cannot be built.'
    }

    $runtimeDirectory = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
    $baseArguments = @(
        '/nologo', '/target:winexe', '/optimize+', '/codepage:65001', "/out:$OutputPath",
        '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll',
        '/reference:System.Web.Extensions.dll', '/reference:System.Xaml.dll'
    )
    # The WPF libraries live in their own subfolder of the .NET Framework directory.
    foreach ($wpfLibrary in 'PresentationFramework', 'PresentationCore', 'WindowsBase', 'UIAutomationTypes') {
        $baseArguments += "/reference:$(Join-Path $runtimeDirectory "WPF\$wpfLibrary.dll")"
    }
    if ($XamlPath) {
        $baseArguments += "/resource:$XamlPath,TbDesk.xaml"
    }

    # An unusable icon must not stop the build, so the last attempt has none.
    $attempts = [System.Collections.Generic.List[object]]::new()
    if ($IconPath -and (Test-Path -LiteralPath $IconPath)) {
        $attempts.Add(@("/win32icon:$IconPath"))
    }
    $attempts.Add(@())

    $output = $null
    foreach ($extraArguments in $attempts) {
        $global:LASTEXITCODE = 0
        $output = & $csc @baseArguments @extraArguments @SourcePath
        if ($LASTEXITCODE -eq 0) {
            return
        }
    }

    throw "Building the screenshot helper failed:`n$($output -join "`n")"
}

function Get-TbClipHelperPath {
    Join-Path (Split-Path -Parent $PSScriptRoot) 'TbClipboardHelper.exe'
}

function Get-TbClipHelperShortcutPath {
    Join-Path ([Environment]::GetFolderPath('Startup')) 'Terminal Board Clipboard.lnk'
}

function Get-TbClipHelperProcess {
    <#
        Every process running the helper exe. That is the tray helper plus, once the
        settings screen was opened (or prepared in the background), a second process
        that keeps the screen ready. -TrayOnly returns just the tray helper.
    #>
    param(
        [switch]$TrayOnly
    )

    # Match on the exe path so a same-named program elsewhere is never touched.
    $helperPath = Get-TbClipHelperPath
    $processes = @(Get-Process -Name 'TbClipboardHelper' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -ieq $helperPath })

    if ($TrayOnly -and $processes.Count -gt 0) {
        $screenProcessIds = @(Get-CimInstance Win32_Process -Filter "Name = 'TbClipboardHelper.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match '--desk|--open' } |
            ForEach-Object { $_.ProcessId })
        $processes = @($processes | Where-Object { $_.Id -notin $screenProcessIds })
    }

    $processes
}

function Get-TbClipHelperStatus {
    [pscustomobject]@{
        Installed = Test-Path -LiteralPath (Get-TbClipHelperPath)
        Running   = @(Get-TbClipHelperProcess -TrayOnly).Count -gt 0
        Autostart = Test-Path -LiteralPath (Get-TbClipHelperShortcutPath)
    }
}

function Start-TbClipHelper {
    $helperPath = Get-TbClipHelperPath
    if (-not (Test-Path -LiteralPath $helperPath)) {
        throw 'The screenshot helper is not installed. Run setup.cmd again.'
    }

    if (@(Get-TbClipHelperProcess -TrayOnly).Count -eq 0) {
        Start-Process -FilePath $helperPath
    }
}

function Stop-TbClipHelper {
    $running = @(Get-TbClipHelperProcess)
    if ($running.Count -eq 0) {
        return
    }

    # Ask it to quit so its tray icon disappears cleanly; force it only if it does not.
    Start-Process -FilePath (Get-TbClipHelperPath) -ArgumentList '--exit' -Wait
    foreach ($process in $running) {
        if (-not $process.WaitForExit(3000)) {
            $process.Kill()
        }
    }
}

function Set-TbClipAutostart {
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    $shortcutPath = Get-TbClipHelperShortcutPath
    if (-not $Enabled) {
        if (Test-Path -LiteralPath $shortcutPath) {
            Remove-Item -LiteralPath $shortcutPath -Force
        }
        return
    }

    $helperPath = Get-TbClipHelperPath
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $helperPath
    $shortcut.WorkingDirectory = Split-Path -Parent $helperPath
    $shortcut.Description = 'Saves screenshots to a file and adds the file path to the clipboard'
    $shortcut.Save()
}

function Get-TbProfilesPath {
    Join-Path (Split-Path -Parent (Get-TbSettingsPath)) 'profiles.json'
}

function Get-TbProfiles {
    $result = [ordered]@{}

    $path = Get-TbProfilesPath
    if (-not (Test-Path -LiteralPath $path)) {
        return $result
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($property in $raw.PSObject.Properties) {
            $value = $property.Value
            $commands = @($value.commands | ForEach-Object { [string]$_ })
            $layout = if ($value.layout -in @('columns', 'rows')) { [string]$value.layout } else { 'columns' }
            $result[$property.Name] = [pscustomobject]@{
                Commands = $commands
                Layout   = $layout
            }
        }
    }
    catch {
        # A damaged profiles file should never prevent tb from running.
    }

    $result
}

function Save-TbProfilesData {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$Profiles
    )

    $path = Get-TbProfilesPath

    if ($Profiles.Count -eq 0) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
        return
    }

    $output = [ordered]@{}
    foreach ($key in $Profiles.Keys) {
        $output[$key] = [ordered]@{
            commands = $Profiles[$key].Commands
            layout   = $Profiles[$key].Layout
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    ($output | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $path -Encoding utf8
}

function Save-TbProfile {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string[]]$Commands,

        [ValidateSet('columns', 'rows')]
        [string]$Layout = 'columns'
    )

    if ($Commands.Count -lt $script:TbMinPaneCount -or $Commands.Count -gt $script:TbMaxPaneCount) {
        throw "A profile needs between $script:TbMinPaneCount and $script:TbMaxPaneCount commands."
    }

    $profiles = Get-TbProfiles
    $profiles[$Name] = [pscustomobject]@{ Commands = $Commands; Layout = $Layout }
    Save-TbProfilesData -Profiles $profiles
}

function Remove-TbProfile {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $profiles = Get-TbProfiles
    if (-not $profiles.Contains($Name)) {
        throw "Profile '$Name' was not found."
    }

    $profiles.Remove($Name)
    Save-TbProfilesData -Profiles $profiles
}

function Get-TbAgentCatalog {
    <#
        What a pane can run. The key is the name the settings screen shows; the
        value is the command the pane starts ('@shell' is a plain terminal).
    #>
    [ordered]@{
        'Terminal (PowerShell)' = $script:TbPlainShell
        'Claude Code'           = 'claude'
        'Codex'                 = 'codex'
        'Antigravity'           = 'agy'
    }
}

function Get-TbDeskSettingsPath {
    Join-Path (Split-Path -Parent (Get-TbSettingsPath)) 'desk.json'
}

function Get-TbJsonValue {
    param(
        [Parameter(Mandatory)]
        $Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    # Reading a missing property throws under StrictMode; this returns $null instead.
    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $property.Value
    }
}

function Get-TbDeskSettings {
    <#
        What the settings screen remembers: the working folder, how many panes,
        the layout, and the command of every pane (always 12 entries; only the
        first Count are used).
    #>
    $settings = [pscustomobject]@{
        Folder = $env:USERPROFILE
        Count  = 5
        Layout = 'columns'
        Panes  = @(1..$script:TbMaxPaneCount | ForEach-Object { $script:TbPlainShell })
    }

    $path = Get-TbDeskSettingsPath
    if (-not (Test-Path -LiteralPath $path)) {
        return $settings
    }

    try {
        $saved = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

        $folder = [string](Get-TbJsonValue -Object $saved -Name 'folder')
        if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) {
            $settings.Folder = $folder
        }

        $count = 0
        if (
            [int]::TryParse([string](Get-TbJsonValue -Object $saved -Name 'count'), [ref]$count) -and
            $count -ge $script:TbMinPaneCount -and
            $count -le $script:TbMaxPaneCount
        ) {
            $settings.Count = $count
        }

        $layout = [string](Get-TbJsonValue -Object $saved -Name 'layout')
        if ($layout -in @('columns', 'rows')) {
            $settings.Layout = $layout
        }

        $savedPanes = @(Get-TbJsonValue -Object $saved -Name 'panes' | ForEach-Object { [string]$_ })
        for ($index = 0; $index -lt [Math]::Min($savedPanes.Count, $script:TbMaxPaneCount); $index++) {
            if ($savedPanes[$index]) {
                $settings.Panes[$index] = $savedPanes[$index]
            }
        }
    }
    catch {
        # A damaged settings file should never stop the screen from opening.
    }

    $settings
}

function Save-TbDeskSettings {
    param(
        [Parameter(Mandatory)]
        [string]$Folder,

        [Parameter(Mandatory)]
        [int]$Count,

        [Parameter(Mandatory)]
        [ValidateSet('columns', 'rows')]
        [string]$Layout,

        [Parameter(Mandatory)]
        [string[]]$Panes
    )

    Assert-TbPaneCount -Count $Count

    $path = Get-TbDeskSettingsPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null

    $data = [ordered]@{
        folder = $Folder
        count  = $Count
        layout = $Layout
        panes  = @($Panes)
    }

    # The settings screen keeps its colour theme and background picture in the same file; do not lose them.
    if (Test-Path -LiteralPath $path) {
        try {
            $existing = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($keepName in 'theme', 'background') {
                $keepValue = Get-TbJsonValue -Object $existing -Name $keepName
                if ($keepValue) {
                    $data[$keepName] = [string]$keepValue
                }
            }
            # Agent names per pane (set on the settings screen) are kept too.
            $keepNames = @(Get-TbJsonValue -Object $existing -Name 'names' | ForEach-Object { [string]$_ })
            if ($keepNames.Count -gt 0) {
                $data['names'] = $keepNames
            }
        }
        catch {
            # A damaged file simply has no theme to keep.
        }
    }

    $data | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
}

function Open-TbDesk {
    <#
        Opens a new maximized window with one pane per chosen agent, every pane
        starting in the chosen folder.
    #>
    param(
        [pscustomobject]$Settings = (Get-TbDeskSettings),

        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $Settings.Folder -PathType Container)) {
        throw "Working folder not found: $($Settings.Folder)"
    }

    # Named panes (banner + tab title) are built by the screenshot helper program; hand the real launch to it.
    if (-not $DryRun) {
        $deskPath = Get-TbDeskSettingsPath
        $hasNames = $false
        try {
            $savedDesk = Get-Content -LiteralPath $deskPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $hasNames = @(Get-TbJsonValue -Object $savedDesk -Name 'names' | Where-Object { $_ }).Count -gt 0
        }
        catch {
            $hasNames = $false
        }
        $helper = Get-TbClipHelperPath
        if ($hasNames -and (Test-Path -LiteralPath $helper)) {
            Start-Process -FilePath $helper -ArgumentList '--open', '--data-dir', ('"{0}"' -f (Split-Path -Parent $deskPath))
            return
        }
    }

    $commands = @($Settings.Panes | Select-Object -First $Settings.Count)
    while ($commands.Count -lt $Settings.Count) {
        $commands += $script:TbPlainShell
    }

    Push-Location -LiteralPath $Settings.Folder
    try {
        Invoke-TerminalBoard -Count $Settings.Count -Layout $Settings.Layout -NewWindow -NoRemember -DryRun:$DryRun -Commands $commands
    }
    finally {
        Pop-Location
    }
}

function Show-TbHelp {
    @'
Terminal Board (tb) - Windows

Layout:
  tb 5              Split the current terminal into 5 equal columns
  tb 3 rows         Split the current terminal into 3 equal rows
  tb                Reuse the previous pane count and layout
  tb 5 --dry-run    Show the Windows Terminal command without running it
  tb 5 --new-window Open the board in a new Windows Terminal window

Workspace (choose how many panes and what each one runs):
  tb ui             Open the settings screen: working folder, number of panes,
                     and what runs in each pane (Terminal, Claude Code, Codex,
                     Antigravity, or any command)
  tb desk           Open the saved workspace right away, without asking again

Screenshots:
  Win+Shift+S, then Ctrl+V in the terminal
                     The background helper saves the picture and adds its file
                     path to the clipboard. Ctrl+V in a terminal pastes the path;
                     Ctrl+V in Word/Paint/chat apps still pastes the picture.
                     (Claude Code also has Alt+V to paste the picture directly)
  tb clip [status]  Show whether the screenshot helper is running
  tb clip on|off    Turn the screenshot helper on/off (also its autostart)
  tb img            Save the picture currently on the clipboard to a file

Multi-agent profiles:
  tb profile set <name> <cmd1,cmd2,...> [rows|columns]
                     Save a profile; each command runs in its own pane
  tb profile list    List saved profiles
  tb profile remove <name>
                     Remove a profile
  tb <profile-name>  Open every pane of the profile, each running its command
                     Example: tb profile set agents "claude,codex", then tb agents

  tb help           Show this help
'@
}

Export-ModuleMember -Function @(
    'Get-TbSettingsPath',
    'Get-TbSettings',
    'Save-TbSettings',
    'Get-TbSplitPlan',
    'Get-TbShellExecutable',
    'ConvertTo-TbCommandArguments',
    'ConvertTo-TbWtArguments',
    'Format-TbCommandPreview',
    'Write-TbLog',
    'Invoke-TbWtCommand',
    'Invoke-TerminalBoard',
    'Get-TbImageDirectory',
    'Save-TbClipboardImage',
    'New-TbIcon',
    'New-TbClipboardHelper',
    'Get-TbClipHelperPath',
    'Get-TbClipHelperStatus',
    'Start-TbClipHelper',
    'Stop-TbClipHelper',
    'Set-TbClipAutostart',
    'Get-TbProfilesPath',
    'Get-TbProfiles',
    'Save-TbProfile',
    'Remove-TbProfile',
    'Get-TbAgentCatalog',
    'Get-TbDeskSettingsPath',
    'Get-TbDeskSettings',
    'Save-TbDeskSettings',
    'Open-TbDesk',
    'Get-TbPaneTitle',
    'Show-TbHelp'
)
