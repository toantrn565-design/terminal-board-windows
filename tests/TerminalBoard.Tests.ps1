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
$testHost = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $testHost) {
    $testHost = Get-Command powershell.exe
}
$cliOutput = & $testHost.Source -NoLogo -NoProfile -File (Join-Path $projectRoot 'tb.ps1') 4 --dry-run
if ($LASTEXITCODE -ne 0) {
    throw 'CLI dry-run failed.'
}
if ($cliOutput -notmatch 'split-pane') {
    throw "CLI dry-run did not generate split panes: $cliOutput"
}

$shimPath = Join-Path $projectRoot 'tb-shim.cmd'
$shimContents = Get-Content -LiteralPath $shimPath -Raw
if ($shimContents -notmatch 'Terminal Board shim' -or $shimContents -notmatch '%~dp0TerminalBoard\\tb.cmd') {
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

$commandArguments = @(ConvertTo-TbCommandArguments -Command 'npm run dev')
Assert-Equal $commandArguments[-2] '-Command' 'Command argv must pass the profile command via -Command.'
Assert-Equal $commandArguments[-1] 'npm run dev' 'Command argv must keep the profile command intact as one token.'

$profileArguments = @(ConvertTo-TbWtArguments -Count 2 -Layout columns -Commands @('claude', 'codex'))
Assert-Equal ($profileArguments -contains '--') $true 'Profile panes must separate wt options from the launched command.'
Assert-Equal $profileArguments[-4] 'codex' 'The last split must run the second profile command before move-focus is appended.'

$savedWtSessionForProfile = $env:WT_SESSION
try {
    $env:WT_SESSION = 'test-session'
    $mismatchFailed = $false
    try {
        Invoke-TerminalBoard -Count 2 -Layout columns -Commands @('claude') -DryRun | Out-Null
    }
    catch {
        $mismatchFailed = $true
    }
    Assert-Equal $mismatchFailed $true 'Commands must match pane count.'
}
finally {
    $env:WT_SESSION = $savedWtSessionForProfile
}

$savedLocalAppData = $env:LOCALAPPDATA
$tempAppDataDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("tb-tests-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempAppDataDirectory -Force | Out-Null
try {
    $env:LOCALAPPDATA = $tempAppDataDirectory

    $emptyProfiles = Get-TbProfiles
    Assert-Equal $emptyProfiles.Count 0 'A fresh install must start with no saved profiles.'

    Save-TbProfile -Name 'agents' -Commands @('claude', 'codex') -Layout 'columns'
    $savedProfiles = Get-TbProfiles
    Assert-Equal $savedProfiles.Count 1 'Saving a profile must persist exactly one entry.'
    Assert-Equal ($savedProfiles['agents'].Commands -join ',') 'claude,codex' 'Saved profile commands must round-trip in order.'
    Assert-Equal $savedProfiles['agents'].Layout 'columns' 'Saved profile layout must round-trip.'

    Remove-TbProfile -Name 'agents'
    $profilesAfterRemoval = Get-TbProfiles
    Assert-Equal $profilesAfterRemoval.Count 0 'Removing the only profile must leave none behind.'

    $removeMissingFailed = $false
    try {
        Remove-TbProfile -Name 'does-not-exist'
    }
    catch {
        $removeMissingFailed = $true
    }
    Assert-Equal $removeMissingFailed $true 'Removing an unknown profile must fail.'
}
finally {
    $env:LOCALAPPDATA = $savedLocalAppData
    Remove-Item -LiteralPath $tempAppDataDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'All Terminal Board tests passed.'
