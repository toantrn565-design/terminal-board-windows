$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/TerminalBoard.psm1'
Import-Module $modulePath -Force

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message`nExpected: $Expected`nActual:   $Actual"
    }
}

$fiveColumns = @(Get-TbSplitPlan -Count 5 -Layout columns)
Assert-Equal $fiveColumns.Count 4 'Five panes need four splits.'
Assert-Equal $fiveColumns[0].Orientation '-V' 'Columns must use vertical splits.'
Assert-Equal ([math]::Round($fiveColumns[0].Size, 6)) 0.8 'First split for five panes must reserve four fifths.'
Assert-Equal ([math]::Round($fiveColumns[1].Size, 6)) 0.75 'Second split must reserve three fourths.'
Assert-Equal ([math]::Round($fiveColumns[2].Size, 6)) 0.666667 'Third split must reserve two thirds.'
Assert-Equal ([math]::Round($fiveColumns[3].Size, 6)) 0.5 'Final split must be equal.'

$threeRows = @(Get-TbSplitPlan -Count 3 -Layout rows)
Assert-Equal $threeRows.Count 2 'Three panes need two splits.'
Assert-Equal $threeRows[0].Orientation '-H' 'Rows must use horizontal splits.'

$onePaneArguments = @(ConvertTo-TbWtArguments -Count 1 -Layout columns)
Assert-Equal ($onePaneArguments -contains 'split-pane') $false 'One pane must not split.'

$newWindowArguments = @(ConvertTo-TbWtArguments -Count 2 -Layout columns -NewWindow -WorkingDirectory 'C:\Work Folder')
Assert-Equal $newWindowArguments[1] 'new' 'Outside Windows Terminal, a new window must be created.'
Assert-Equal ($newWindowArguments -contains 'C:\Work Folder') $true 'New window must retain the requested working directory.'
$newWindowFirstSeparator = [array]::IndexOf($newWindowArguments, ';')
if ($newWindowFirstSeparator -lt 1 -or $newWindowArguments[$newWindowFirstSeparator + 1] -ne 'split-pane') {
    throw 'New windows must separate new-tab from the first split-pane command.'
}

$fivePaneArguments = @(ConvertTo-TbWtArguments -Count 5 -Layout columns)
Assert-Equal (($fivePaneArguments | Where-Object { $_ -eq 'split-pane' }).Count) 4 'Generated command must contain four split operations.'
Assert-Equal (($fivePaneArguments | Where-Object { $_ -eq '-D' }).Count) 4 'Every new pane must duplicate the active terminal profile.'
Assert-Equal $fivePaneArguments[2] 'split-pane' 'Existing windows must not have a separator before the first split.'
Assert-Equal ($fivePaneArguments[-2]) 'move-focus' 'Command must restore focus after splitting.'
Assert-Equal ($fivePaneArguments[-1]) 'first' 'Focus must return to the first pane.'

$preview = Format-TbCommandPreview -Arguments $fivePaneArguments
if (-not $preview.StartsWith('wt.exe -w 0')) {
    throw "Unexpected preview: $preview"
}

$invalidCountFailed = $false
try {
    Get-TbSplitPlan -Count 13 | Out-Null
}
catch {
    $invalidCountFailed = $true
}
Assert-Equal $invalidCountFailed $true 'Counts above the supported maximum must fail.'

$projectRoot = Split-Path -Parent $PSScriptRoot
$cliOutput = & pwsh.exe -NoLogo -NoProfile -File (Join-Path $projectRoot 'tb.ps1') 4 --dry-run
if ($LASTEXITCODE -ne 0) {
    throw 'CLI dry-run failed.'
}
if ($cliOutput -notmatch 'split-pane') {
    throw "CLI dry-run did not generate split panes: $cliOutput"
}

$shimPath = Join-Path $projectRoot 'tb-shim.cmd'
$shimContents = Get-Content -LiteralPath $shimPath -Raw
if ($shimContents -notmatch 'Terminal Board shim' -or $shimContents -notmatch 'TerminalBoard\\bin\\tb.cmd') {
    throw 'WindowsApps shim does not point to the installed Terminal Board command.'
}

$savedWtSession = $env:WT_SESSION
try {
    $env:WT_SESSION = 'test-session'
    $singlePaneOutput = Invoke-TerminalBoard -Count 1 -Layout columns -DryRun
    Assert-Equal $singlePaneOutput 'Khong can chia: pane hien tai da la mot terminal.' 'One pane inside Windows Terminal must be a no-op.'
}
finally {
    $env:WT_SESSION = $savedWtSession
}

Write-Host 'All Terminal Board tests passed.'
