[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$CountOrCommand,

    [Parameter(Position = 1)]
    [string]$Layout,

    [Alias('dry-run')]
    [switch]$DryRun,

    [Alias('no-remember')]
    [switch]$NoRemember,

    [Alias('new-window')]
    [switch]$NewWindow,

    [Alias('h')]
    [switch]$Help,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'src/TerminalBoard.psm1'
Import-Module $modulePath -Force

try {
    if ($Help -or $CountOrCommand -in @('help', '--help', '-h', '/?')) {
        Show-TbHelp
        exit 0
    }

    if ($CountOrCommand -in @('img', 'image', 'paste')) {
        $savedPath = Save-TbClipboardImage
        Write-Host "Saved picture: $savedPath"
        Write-Host 'The path was copied to the clipboard - paste it (Ctrl+V) for the agent.'
        exit 0
    }

    if ($CountOrCommand -eq 'ui') {
        $helperPath = Get-TbClipHelperPath
        if (-not (Test-Path -LiteralPath $helperPath)) {
            throw 'The settings screen is not installed. Run setup.cmd again. You can still use: tb 5, tb desk.'
        }
        Start-Process -FilePath $helperPath -ArgumentList '--desk'
        exit 0
    }

    if ($CountOrCommand -eq 'desk') {
        $deskResult = Open-TbDesk -DryRun:$DryRun
        if ($null -ne $deskResult) {
            $deskResult
        }
        exit 0
    }

    if ($CountOrCommand -eq 'clip') {
        $clipAction = if ($Layout) { $Layout } else { 'status' }
        switch ($clipAction) {
            'on' {
                Set-TbClipAutostart -Enabled $true
                Start-TbClipHelper
                Write-Host 'Screenshot helper turned on (it also starts with Windows).'
                Write-Host 'Take a screenshot (Win+Shift+S), then press Ctrl+V in the terminal to paste the picture path.'
                exit 0
            }
            'off' {
                Stop-TbClipHelper
                Set-TbClipAutostart -Enabled $false
                Write-Host 'Screenshot helper turned off. Turn it back on with: tb clip on'
                exit 0
            }
            'status' {
                $clipStatus = Get-TbClipHelperStatus
                if (-not $clipStatus.Installed) {
                    Write-Host 'The screenshot helper is not installed. Run setup.cmd again.'
                }
                else {
                    Write-Host "Running: $(if ($clipStatus.Running) { 'yes' } else { 'no' })"
                    Write-Host "Starts with Windows: $(if ($clipStatus.Autostart) { 'yes' } else { 'no' })"
                    if (-not $clipStatus.Running) {
                        Write-Host 'Turn it on with: tb clip on'
                    }
                }
                exit 0
            }
            default {
                throw "Unknown clip command: '$clipAction'. Use: tb clip on|off|status"
            }
        }
    }

    if ($CountOrCommand -eq 'profile') {
        switch ($Layout) {
            'set' {
                $name = $Rest[0]
                $commandsArg = $Rest[1]
                $layoutArg = if ($Rest.Count -ge 3 -and $Rest[2]) { $Rest[2] } else { 'columns' }

                if (-not $name -or -not $commandsArg) {
                    throw 'Usage: tb profile set <name> <cmd1,cmd2,...> [rows|columns]'
                }
                if ($layoutArg -notin @('columns', 'rows')) {
                    throw "Invalid layout: '$layoutArg'. Use columns or rows."
                }

                $commands = @($commandsArg -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                Save-TbProfile -Name $name -Commands $commands -Layout $layoutArg
                Write-Host "Saved profile '$name' with $($commands.Count) command(s) ($($commands -join ', '))."
                exit 0
            }
            'list' {
                $profiles = Get-TbProfiles
                if ($profiles.Count -eq 0) {
                    Write-Host 'No profiles yet. Create one with: tb profile set <name> <cmd1,cmd2,...>'
                }
                else {
                    foreach ($key in $profiles.Keys) {
                        $profileInfo = $profiles[$key]
                        Write-Host "$key [$($profileInfo.Layout)] -> $($profileInfo.Commands -join ', ')"
                    }
                }
                exit 0
            }
            'remove' {
                $name = $Rest[0]
                if (-not $name) {
                    throw 'Usage: tb profile remove <name>'
                }
                Remove-TbProfile -Name $name
                Write-Host "Removed profile '$name'."
                exit 0
            }
            default {
                throw "Unknown profile command: '$Layout'. Use: tb profile set|list|remove"
            }
        }
    }

    if ($Layout -and $Layout -notin @('columns', 'rows')) {
        throw "Invalid layout: '$Layout'. Use columns or rows."
    }

    $settings = Get-TbSettings
    $count = $settings.count
    $selectedLayout = if ($Layout) { $Layout } else { $settings.layout }
    $commands = @()

    if ($CountOrCommand) {
        $parsedCount = 0
        if ([int]::TryParse($CountOrCommand, [ref]$parsedCount)) {
            $count = $parsedCount
        }
        else {
            $profiles = Get-TbProfiles
            if (-not $profiles.Contains($CountOrCommand)) {
                throw "'$CountOrCommand' is neither a valid pane count nor a saved profile. See: tb profile list"
            }
            $profileInfo = $profiles[$CountOrCommand]
            $commands = $profileInfo.Commands
            $count = $commands.Count
            $selectedLayout = if ($Layout) { $Layout } else { $profileInfo.Layout }
        }
    }

    $result = Invoke-TerminalBoard `
        -Count $count `
        -Layout $selectedLayout `
        -DryRun:$DryRun `
        -NoRemember:$NoRemember `
        -NewWindow:$NewWindow `
        -Commands $commands

    if ($null -ne $result) {
        $result
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
