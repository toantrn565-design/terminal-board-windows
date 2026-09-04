Set-StrictMode -Version Latest

$script:TbMinPaneCount = 1
$script:TbMaxPaneCount = 12

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
        throw "So terminal phai tu $script:TbMinPaneCount den $script:TbMaxPaneCount."
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

    @((Get-TbShellExecutable), '-NoExit', '-Command', $Command)
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
        $arguments.Add('new-tab')
        $arguments.Add('-d')
        $arguments.Add($WorkingDirectory)
        $arguments.Add('--title')
        $arguments.Add('TB 1')
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
        $arguments.Add('split-pane')
        $arguments.Add($split.Orientation)
        $arguments.Add('-s')
        $arguments.Add($split.Size.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture))
        $arguments.Add('-D')
        $arguments.Add('--title')
        $arguments.Add("TB $($split.PaneNumber)")
        $arguments.Add('--suppressApplicationTitle')

        $commandIndex = $split.PaneNumber - 1
        if ($Commands.Count -ge $split.PaneNumber -and $Commands[$commandIndex]) {
            $arguments.Add('--')
            foreach ($token in (ConvertTo-TbCommandArguments -Command $Commands[$commandIndex])) {
                $arguments.Add($token)
            }
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
    & $Wt.Source @Arguments
    $exitCode = $LASTEXITCODE
    Write-TbLog -Message "exit=$exitCode"

    if ($exitCode -ne 0) {
        throw "Windows Terminal tra ve ma loi $exitCode."
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
        throw 'So lenh trong profile phai bang so pane.'
    }

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Terminal Board chi ho tro Windows.'
    }

    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $wt -and -not $DryRun) {
        throw 'Khong tim thay Windows Terminal (wt.exe). Hay cai Windows Terminal truoc.'
    }

    # A profile assigns a command to pane 1 too, which only a fresh window
    # can accept - the pane already running the current shell cannot be
    # redirected into a different process.
    $openNewWindow = $NewWindow -or -not [bool]$env:WT_SESSION -or $Commands.Count -gt 0

    if ($Count -eq 1 -and -not $openNewWindow) {
        if ($DryRun) {
            return 'Khong can chia: pane hien tai da la mot terminal.'
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

    # Invoke each operation separately. This avoids Windows PowerShell and
    # Windows Terminal disagreeing about semicolon command separators.
    $windowTarget = '0'
    if ($openNewWindow) {
        $windowTarget = "tb-$PID-$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
        $startArguments = @(
            '-w', $windowTarget,
            'new-tab',
            '-d', (Get-Location).Path,
            '--title', 'TB 1',
            '--suppressApplicationTitle'
        )
        if ($Commands.Count -ge 1 -and $Commands[0]) {
            $startArguments += '--'
            $startArguments += (ConvertTo-TbCommandArguments -Command $Commands[0])
        }
        Invoke-TbWtCommand -Wt $wt -Arguments $startArguments
        Start-Sleep -Milliseconds 250
    }

    foreach ($split in (Get-TbSplitPlan -Count $Count -Layout $Layout)) {
        $splitArguments = @(
            '-w', $windowTarget,
            'split-pane',
            $split.Orientation,
            '-s', $split.Size.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture),
            '-D',
            '--title', "TB $($split.PaneNumber)",
            '--suppressApplicationTitle'
        )
        $commandIndex = $split.PaneNumber - 1
        if ($Commands.Count -ge $split.PaneNumber -and $Commands[$commandIndex]) {
            $splitArguments += '--'
            $splitArguments += (ConvertTo-TbCommandArguments -Command $Commands[$commandIndex])
        }
        Invoke-TbWtCommand -Wt $wt -Arguments $splitArguments
        Start-Sleep -Milliseconds 100
    }

    if ($Count -gt 1) {
        Invoke-TbWtCommand -Wt $wt -Arguments @('-w', $windowTarget, 'move-focus', 'first')
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
        throw "Khong tim thay worker doc clipboard: $workerPath"
    }

    $powershellExe = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $powershellExe) {
        throw 'Khong tim thay powershell.exe de doc clipboard.'
    }

    & $powershellExe.Source -NoLogo -NoProfile -Sta -File $workerPath -Path $path
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 2) {
        throw 'Khong co anh nao trong clipboard. Chup man hinh (Win+Shift+S) hoac Copy anh roi thu lai.'
    }
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $path)) {
        throw 'Khong doc duoc anh tu clipboard.'
    }

    $path
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
        throw "Profile phai co tu $script:TbMinPaneCount den $script:TbMaxPaneCount lenh."
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
        throw "Khong tim thay profile '$Name'."
    }

    $profiles.Remove($Name)
    Save-TbProfilesData -Profiles $profiles
}

function Show-TbHelp {
    @'
Terminal Board (tb) - Windows

Bo cuc:
  tb 5              Chia terminal hien tai thanh 5 cot bang nhau
  tb 3 rows         Chia terminal hien tai thanh 3 hang bang nhau
  tb                Dung lai so luong va bo cuc lan truoc
  tb 5 --dry-run    Xem lenh Windows Terminal ma khong thay doi giao dien
  tb 5 --new-window Mo board trong mot cua so Windows Terminal moi

Anh chup man hinh:
  tb img            Luu anh dang co trong clipboard ra file va copy duong
                     dan file do vao clipboard de dan (Ctrl+V) cho agent

Profile nhieu agent:
  tb profile set <ten> <lenh1,lenh2,...> [rows|columns]
                     Luu mot profile, moi lenh chay trong mot pane rieng
  tb profile list    Liet ke cac profile da luu
  tb profile remove <ten>
                     Xoa mot profile
  tb <ten-profile>   Mo tat ca pane cua profile, moi pane chay agent tuong ung
                     Vi du: tb profile set agents "claude,codex" roi tb agents

  tb help           Hien tro giup

Yeu cau: Windows Terminal. Gioi han: 1-12 terminal.
Moi pane la mot terminal Windows doc lap.
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
    'Get-TbProfilesPath',
    'Get-TbProfiles',
    'Save-TbProfile',
    'Remove-TbProfile',
    'Show-TbHelp'
)
