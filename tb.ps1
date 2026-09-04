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

    if ($CountOrCommand -in @('img', 'image', 'clip', 'paste')) {
        $savedPath = Save-TbClipboardImage
        Write-Host "Da luu anh: $savedPath"
        Write-Host 'Duong dan da duoc copy vao clipboard - dan (Ctrl+V) cho agent.'
        exit 0
    }

    if ($CountOrCommand -eq 'profile') {
        switch ($Layout) {
            'set' {
                $name = $Rest[0]
                $commandsArg = $Rest[1]
                $layoutArg = if ($Rest.Count -ge 3 -and $Rest[2]) { $Rest[2] } else { 'columns' }

                if (-not $name -or -not $commandsArg) {
                    throw 'Cu phap: tb profile set <ten> <lenh1,lenh2,...> [rows|columns]'
                }
                if ($layoutArg -notin @('columns', 'rows')) {
                    throw "Bo cuc khong hop le: '$layoutArg'. Dung columns hoac rows."
                }

                $commands = @($commandsArg -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                Save-TbProfile -Name $name -Commands $commands -Layout $layoutArg
                Write-Host "Da luu profile '$name' voi $($commands.Count) lenh ($($commands -join ', '))."
                exit 0
            }
            'list' {
                $profiles = Get-TbProfiles
                if ($profiles.Count -eq 0) {
                    Write-Host 'Chua co profile nao. Tao bang: tb profile set <ten> <lenh1,lenh2,...>'
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
                    throw 'Cu phap: tb profile remove <ten>'
                }
                Remove-TbProfile -Name $name
                Write-Host "Da xoa profile '$name'."
                exit 0
            }
            default {
                throw "Lenh profile khong hop le: '$Layout'. Dung: tb profile set|list|remove"
            }
        }
    }

    if ($Layout -and $Layout -notin @('columns', 'rows')) {
        throw "Bo cuc khong hop le: '$Layout'. Dung columns hoac rows."
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
                throw "'$CountOrCommand' khong phai so terminal hop le va cung khong phai profile da luu. Xem: tb profile list"
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
