[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$CountOrCommand,

    [Parameter(Position = 1)]
    [ValidateSet('columns', 'rows')]
    [string]$Layout,

    [Alias('dry-run')]
    [switch]$DryRun,

    [Alias('no-remember')]
    [switch]$NoRemember,

    [Alias('new-window')]
    [switch]$NewWindow,

    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'src/TerminalBoard.psm1'
Import-Module $modulePath -Force

try {
    if ($Help -or $CountOrCommand -in @('help', '--help', '-h', '/?')) {
        Show-TbHelp
        exit 0
    }

    $settings = Get-TbSettings
    $count = $settings.count
    $selectedLayout = if ($Layout) { $Layout } else { $settings.layout }

    if ($CountOrCommand) {
        $parsedCount = 0
        if (-not [int]::TryParse($CountOrCommand, [ref]$parsedCount)) {
            throw "'$CountOrCommand' khong phai so terminal hop le. Vi du: tb 5"
        }
        $count = $parsedCount
    }

    $result = Invoke-TerminalBoard `
        -Count $count `
        -Layout $selectedLayout `
        -DryRun:$DryRun `
        -NoRemember:$NoRemember `
        -NewWindow:$NewWindow

    if ($null -ne $result) {
        $result
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
