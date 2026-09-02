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

function ConvertTo-TbWtArguments {
    param(
        [Parameter(Mandatory)]
        [int]$Count,

        [ValidateSet('columns', 'rows')]
        [string]$Layout = 'columns',

        [switch]$NewWindow,

        [string]$WorkingDirectory = (Get-Location).Path
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

        [switch]$NewWindow
    )

    Assert-TbPaneCount -Count $Count

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Terminal Board chi ho tro Windows.'
    }

    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $wt -and -not $DryRun) {
        throw 'Khong tim thay Windows Terminal (wt.exe). Hay cai Windows Terminal truoc.'
    }

    $openNewWindow = $NewWindow -or -not [bool]$env:WT_SESSION

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
        $arguments = ConvertTo-TbWtArguments -Count $Count -Layout $Layout -NewWindow:$openNewWindow
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
        Invoke-TbWtCommand -Wt $wt -Arguments $splitArguments
        Start-Sleep -Milliseconds 100
    }

    if ($Count -gt 1) {
        Invoke-TbWtCommand -Wt $wt -Arguments @('-w', $windowTarget, 'move-focus', 'first')
    }
}

function Show-TbHelp {
    @'
Terminal Board (tb) - Windows

Su dung:
  tb 5              Chia terminal hien tai thanh 5 cot bang nhau
  tb 3 rows         Chia terminal hien tai thanh 3 hang bang nhau
  tb                Dung lai so luong va bo cuc lan truoc
  tb 5 --dry-run    Xem lenh Windows Terminal ma khong thay doi giao dien
  tb 5 --new-window Mo board trong mot cua so Windows Terminal moi
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
    'ConvertTo-TbWtArguments',
    'Format-TbCommandPreview',
    'Write-TbLog',
    'Invoke-TbWtCommand',
    'Invoke-TerminalBoard',
    'Show-TbHelp'
)
