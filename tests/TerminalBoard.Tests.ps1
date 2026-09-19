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
Assert-Equal ($newWindowArguments -ccontains '-M') $true 'A new board window must open maximized so the taskbar stays visible.'
Assert-Equal ($newWindowArguments -ccontains '-F') $false 'A new board window must never open fullscreen.'
$newWindowFirstSeparator = [array]::IndexOf($newWindowArguments, ';')
if ($newWindowFirstSeparator -lt 1 -or $newWindowArguments[$newWindowFirstSeparator + 1] -ne 'split-pane') {
    throw 'New windows must separate new-tab from the first split-pane command.'
}

$fivePaneArguments = @(ConvertTo-TbWtArguments -Count 5 -Layout columns)
Assert-Equal (($fivePaneArguments | Where-Object { $_ -eq 'split-pane' }).Count) 4 'Generated command must contain four split operations.'
Assert-Equal (($fivePaneArguments | Where-Object { $_ -eq '-D' }).Count) 4 'Every new pane must duplicate the active terminal profile.'
Assert-Equal $fivePaneArguments[2] 'split-pane' 'Existing windows must not have a separator before the first split.'
Assert-Equal ($fivePaneArguments -ccontains '-M') $false 'Splitting an existing window must not change that window''s size.'
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

& $testHost.Source -NoLogo -NoProfile -File (Join-Path $projectRoot 'tb.ps1') clip status | Out-Null
Assert-Equal $LASTEXITCODE 0 'tb clip status must succeed whether or not the helper is installed.'

# Windows PowerShell 5.1 turns a child process's stderr into a terminating error under 'Stop'.
$savedErrorPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & $testHost.Source -NoLogo -NoProfile -File (Join-Path $projectRoot 'tb.ps1') clip nonsense 2>$null | Out-Null
    $unknownClipExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $savedErrorPreference
}
Assert-Equal ($unknownClipExitCode -ne 0) $true 'tb clip with an unknown action must fail.'

$deskDryRun = & $testHost.Source -NoLogo -NoProfile -File (Join-Path $projectRoot 'tb.ps1') desk --dry-run
Assert-Equal $LASTEXITCODE 0 'tb desk --dry-run must succeed.'
Assert-Equal ((@($deskDryRun) -join ' ') -match 'new-tab') $true 'tb desk must open a new window.'

$xamlPath = Join-Path $projectRoot 'src\TbDesk.xaml'
$xamlText = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
[xml]$xamlDocument = $xamlText
Assert-Equal $xamlDocument.DocumentElement.LocalName 'Window' 'The settings screen layout must be a WPF window.'
$xamlNames = @([regex]::Matches($xamlText, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
foreach ($requiredName in 'Header', 'ThemeHost', 'BgImage', 'ArtLayer', 'BtnImage', 'BtnMin', 'BtnClose', 'TxtFolder', 'BtnBrowse', 'BtnMinus', 'BtnPlus', 'TxtCount', 'ChipCols', 'ChipRows', 'RowsHost', 'PreviewGrid', 'PreviewInfo', 'PresetsHost', 'StatusText', 'BtnSave', 'BtnOpen') {
    Assert-Equal ($xamlNames -contains $requiredName) $true "The settings screen layout must define $requiredName."
}

# The product is English-only for a global audience: no Vietnamese letters (U+00C0-U+1EF9) may
# creep back into anything the user reads (screens, messages, scripts, docs).
$englishOnlyFiles = @(
    Get-ChildItem -LiteralPath $projectRoot -File | Where-Object { $_.Extension -in '.ps1', '.cmd', '.md' }
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -File
)
foreach ($englishOnlyFile in $englishOnlyFiles) {
    $englishOnlyText = [System.IO.File]::ReadAllText($englishOnlyFile.FullName, [System.Text.Encoding]::UTF8)
    $vietnameseMatch = [regex]::Match($englishOnlyText, ('[' + [char]0x00C0 + '-' + [char]0x1EF9 + ']'))
    Assert-Equal $vietnameseMatch.Success $false "$($englishOnlyFile.Name) must be English only (found '$($vietnameseMatch.Value)')."
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
    Assert-Equal $singlePaneOutput 'Nothing to split: the current pane is already a single terminal.' 'One pane inside Windows Terminal must be a no-op.'
}
finally {
    $env:WT_SESSION = $savedWtSession
}

$commandArguments = @(ConvertTo-TbCommandArguments -Command 'npm run dev')
Assert-Equal $commandArguments[-2] '-Command' 'Command argv must pass the profile command via -Command.'
Assert-Equal $commandArguments[-1] 'npm run dev' 'Command argv must keep the profile command intact as one token.'

$semicolonArguments = @(ConvertTo-TbCommandArguments -Command 'cd app; npm run dev')
Assert-Equal $semicolonArguments[-1] 'cd app\; npm run dev' 'Semicolons must be escaped so Windows Terminal does not split the pane command.'

Assert-Equal (Get-TbPaneTitle -Command '' -Number 3) 'TB 3' 'Panes without a command keep the plain TB title.'
Assert-Equal (Get-TbPaneTitle -Command 'claude' -Number 1) '1 - Claude Code' 'A Claude pane must be titled by its agent.'
Assert-Equal (Get-TbPaneTitle -Command '@shell' -Number 2) '2 - Terminal' 'A plain terminal pane must be titled Terminal.'
Assert-Equal (Get-TbPaneTitle -Command 'codex' -Number 4) '4 - Codex' 'A Codex pane must be titled by its agent.'
Assert-Equal (Get-TbPaneTitle -Command 'npm run dev' -Number 5) '5 - npm run dev' 'A custom command is shown as typed.'
Assert-Equal (Get-TbPaneTitle -Command ('x' * 40) -Number 6) ('6 - ' + ('x' * 24)) 'A very long custom command must be shortened in the title.'

$plainShellArguments = @(ConvertTo-TbCommandArguments -Command '@shell')
Assert-Equal ($plainShellArguments -contains '-Command') $false 'A plain terminal pane must not run any command.'
Assert-Equal $plainShellArguments[-1] '-NoExit' 'A plain terminal pane must keep its shell open.'

$profileArguments = @(ConvertTo-TbWtArguments -Count 2 -Layout columns -Commands @('claude', 'codex'))
Assert-Equal ($profileArguments -contains '--') $true 'Profile panes must separate wt options from the launched command.'
Assert-Equal $profileArguments[-4] 'codex' 'The last split must run the second profile command before move-focus is appended.'

$profileSplitArguments = @(ConvertTo-TbWtArguments -Count 2 -Layout columns -Commands @('claude', 'codex') -WorkingDirectory 'C:\Work Folder')
Assert-Equal ($profileSplitArguments -ccontains '-D') $false 'A pane that runs a command must not use -D, or Windows Terminal ignores the command.'
$profileStartDirectoryIndex = [array]::IndexOf($profileSplitArguments, '-d')
if ($profileStartDirectoryIndex -lt 0) {
    throw 'A pane that runs a command must set an explicit start directory.'
}
Assert-Equal $profileSplitArguments[$profileStartDirectoryIndex + 1] 'C:\Work Folder' 'A pane that runs a command must start in the working directory.'

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

    $fakeWtDirectory = Join-Path $tempAppDataDirectory 'fake-wt'
    New-Item -ItemType Directory -Path $fakeWtDirectory -Force | Out-Null
    $fakeWtPath = Join-Path $fakeWtDirectory 'fakewt.cmd'
    Set-Content -LiteralPath $fakeWtPath -Encoding ascii -Value @('@echo off', 'exit /b %FAKE_WT_EXIT%')
    $fakeWt = Get-Command $fakeWtPath
    $tbLogPath = Join-Path $tempAppDataDirectory 'TerminalBoard\tb.log'

    $env:FAKE_WT_EXIT = '0'
    Invoke-TbWtCommand -Wt $fakeWt -Arguments @('-w', '0', 'move-focus', 'first')
    $successLogLines = @(Get-Content -LiteralPath $tbLogPath | Where-Object { $_ -match 'exit=0' })
    Assert-Equal $successLogLines.Count 1 'A successful wt call must log exit=0.'

    $env:FAKE_WT_EXIT = '3'
    $wtFailureThrew = $false
    try {
        Invoke-TbWtCommand -Wt $fakeWt -Arguments @('-w', '0', 'move-focus', 'first')
    }
    catch {
        $wtFailureThrew = $true
    }
    Assert-Equal $wtFailureThrew $true 'A non-zero wt exit code must fail the command.'
    Remove-Item -LiteralPath Env:FAKE_WT_EXIT -ErrorAction SilentlyContinue

    # wscript //B is a silent GUI-subsystem program. Like wt.exe opening a new
    # window, it returns without ever setting $LASTEXITCODE.
    $wscript = Get-Command wscript.exe -ErrorAction SilentlyContinue
    if ($wscript) {
        $noopScriptPath = Join-Path $fakeWtDirectory 'noop.vbs'
        Set-Content -LiteralPath $noopScriptPath -Encoding ascii -Value "' no-op"
        Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue

        $guiLaunchError = ''
        try {
            Invoke-TbWtCommand -Wt $wscript -Arguments @('//B', '//Nologo', $noopScriptPath)
        }
        catch {
            $guiLaunchError = $_.Exception.Message
        }
        Assert-Equal $guiLaunchError '' 'A launch that never sets LASTEXITCODE (wt.exe opening a new window) must not fail.'
    }

    $defaultDesk = Get-TbDeskSettings
    Assert-Equal $defaultDesk.Count 5 'The settings screen must default to five panes.'
    Assert-Equal $defaultDesk.Layout 'columns' 'The settings screen must default to columns.'
    Assert-Equal $defaultDesk.Panes.Count 12 'Settings must always carry a command for every possible pane.'
    Assert-Equal $defaultDesk.Panes[0] '@shell' 'Panes must default to a plain terminal.'
    $agentCatalog = Get-TbAgentCatalog
    Assert-Equal (@($agentCatalog.Keys) -join '|') 'Terminal (PowerShell)|Claude Code|Codex|Antigravity' 'The agent list must offer terminal, Claude Code, Codex and Antigravity.'
    Assert-Equal $agentCatalog['Antigravity'] 'agy' 'Antigravity runs through its agy command line.'

    $deskFolder = Join-Path $tempAppDataDirectory 'project folder'
    New-Item -ItemType Directory -Path $deskFolder -Force | Out-Null
    Save-TbDeskSettings -Folder $deskFolder -Count 3 -Layout 'rows' -Panes @('claude', 'codex', '@shell')
    $savedDesk = Get-TbDeskSettings
    Assert-Equal $savedDesk.Folder $deskFolder 'The working folder must round-trip.'
    Assert-Equal $savedDesk.Count 3 'The pane count must round-trip.'
    Assert-Equal $savedDesk.Layout 'rows' 'The layout must round-trip.'
    Assert-Equal ($savedDesk.Panes[0..2] -join ',') 'claude,codex,@shell' 'The pane commands must round-trip in order.'
    Assert-Equal $savedDesk.Panes[3] '@shell' 'Panes that were not saved must default to a plain terminal.'
    Assert-Equal $savedDesk.Panes.Count 12 'Loaded settings must still carry twelve panes.'

    Set-Content -LiteralPath (Get-TbDeskSettingsPath) -Value '{"folder":"Z:\\does\\not\\exist","count":99,"layout":"diagonal","panes":["claude"]}'
    $cleanedDesk = Get-TbDeskSettings
    Assert-Equal $cleanedDesk.Count 5 'An impossible pane count must fall back to the default.'
    Assert-Equal $cleanedDesk.Layout 'columns' 'An unknown layout must fall back to the default.'
    Assert-Equal $cleanedDesk.Folder $env:USERPROFILE 'A missing folder must fall back to the profile folder.'
    Assert-Equal $cleanedDesk.Panes[0] 'claude' 'Valid parts of a partly wrong file must still be used.'

    Set-Content -LiteralPath (Get-TbDeskSettingsPath) -Value '{ this is not json'
    Assert-Equal (Get-TbDeskSettings).Count 5 'A damaged settings file must not stop the screen from opening.'

    Set-Content -LiteralPath (Get-TbDeskSettingsPath) -Value '{"folder":"C:\\","count":2,"layout":"rows","theme":"burgundy","panes":["claude","codex"]}'
    Save-TbDeskSettings -Folder $deskFolder -Count 3 -Layout 'columns' -Panes @('codex', 'codex', 'codex')
    $themeAfterSave = (Get-Content -LiteralPath (Get-TbDeskSettingsPath) -Raw | ConvertFrom-Json).theme
    Assert-Equal $themeAfterSave 'burgundy' 'Saving from PowerShell must keep the colour theme chosen on the settings screen.'

    Set-Content -LiteralPath (Get-TbDeskSettingsPath) -Value '{"folder":"C:\\","count":2,"layout":"rows","theme":"emerald","background":"background.png","panes":["claude","codex"]}'
    Save-TbDeskSettings -Folder $deskFolder -Count 3 -Layout 'columns' -Panes @('codex', 'codex', 'codex')
    $savedAppearance = Get-Content -LiteralPath (Get-TbDeskSettingsPath) -Raw | ConvertFrom-Json
    Assert-Equal $savedAppearance.background 'background.png' 'Saving from PowerShell must keep the background picture chosen on the settings screen.'
    Assert-Equal $savedAppearance.theme 'emerald' 'Saving from PowerShell must keep the colour theme next to the picture.'

    $deskPreview = Open-TbDesk -Settings ([pscustomobject]@{ Folder = $deskFolder; Count = 3; Layout = 'columns'; Panes = @('claude', '@shell', 'agy') }) -DryRun
    Assert-Equal $deskPreview.StartsWith('wt.exe -w new -M new-tab') $true 'The board must open in a new maximized window.'
    Assert-Equal ($deskPreview.Contains($deskFolder)) $true 'Every pane must start in the chosen folder.'
    Assert-Equal ($deskPreview -cmatch ' -D ') $false 'Panes that run something must not use -D, which makes Windows Terminal ignore the command.'
    Assert-Equal (([regex]::Matches($deskPreview, 'split-pane')).Count) 2 'Three panes need two splits.'
    foreach ($expectedTitle in '1 - Claude Code', '2 - Terminal', '3 - Antigravity') {
        Assert-Equal ($deskPreview.Contains($expectedTitle)) $true "Panes must be titled by what they run ($expectedTitle)."
    }
    foreach ($expectedCommand in 'claude', 'agy') {
        Assert-Equal ($deskPreview.Contains($expectedCommand)) $true "The $expectedCommand pane must run its command."
    }

    $missingFolderFailed = $false
    try {
        Open-TbDesk -Settings ([pscustomobject]@{ Folder = (Join-Path $tempAppDataDirectory 'nope'); Count = 1; Layout = 'columns'; Panes = @('@shell') }) -DryRun | Out-Null
    }
    catch {
        $missingFolderFailed = $true
    }
    Assert-Equal $missingFolderFailed $true 'Opening the board in a missing folder must fail with a clear error.'

    $iconTestPath = Join-Path $tempAppDataDirectory 'test.ico'
    New-TbIcon -Path $iconTestPath
    $iconBytes = [System.IO.File]::ReadAllBytes($iconTestPath)
    Assert-Equal (($iconBytes[0..3]) -join ',') '0,0,1,0' 'The generated icon must be a valid .ico file.'
    Assert-Equal ($iconBytes.Length -gt 100) $true 'The generated icon must not be empty.'

    $clipHelperStatus = Get-TbClipHelperStatus
    Assert-Equal (($clipHelperStatus.PSObject.Properties.Name | Sort-Object) -join ',') 'Autostart,Installed,Running' 'Clip helper status must report install, run and autostart state.'

    $cscPath = Join-Path ([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    if (Test-Path -LiteralPath $cscPath) {
        $helperBuildDirectory = Join-Path $tempAppDataDirectory 'helper-build'
        New-Item -ItemType Directory -Path $helperBuildDirectory -Force | Out-Null
        $helperExePath = Join-Path $helperBuildDirectory 'TbClipboardHelper.exe'
        New-TbClipboardHelper `
            -SourcePath (Join-Path $projectRoot 'src\TbClipboardHelper.cs'), (Join-Path $projectRoot 'src\TbDeskWindow.cs') `
            -XamlPath $xamlPath `
            -OutputPath $helperExePath
        Assert-Equal (Test-Path -LiteralPath $helperExePath) $true 'The clipboard helper and settings screen must compile.'

        # Load from bytes so the temp folder can be deleted afterwards.
        $helperAssembly = [System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($helperExePath))
        Assert-Equal ($helperAssembly.GetManifestResourceNames() -contains 'TbDesk.xaml') $true 'The settings screen layout must be embedded in the exe.'
        Add-Type -AssemblyName System.Drawing

        $isPlainPicture = { param([string[]]$Formats) [TerminalBoard.ClipboardInspector]::IsPlainPicture($Formats) }
        Assert-Equal (& $isPlainPicture @('CF_BITMAP', 'CF_DIB', 'CF_DIBV5')) $true 'A plain screenshot must be recognised.'
        Assert-Equal (& $isPlainPicture @('DataObject', 'System.Drawing.Bitmap', 'CF_BITMAP', 'Ole Private Data', 'CF_LOCALE', 'CF_DIB', 'CF_DIBV5')) $true 'A picture copied from a .NET or OLE program must be recognised.'
        Assert-Equal (& $isPlainPicture @('CF_BITMAP', 'CF_DIB', 'CF_UNICODETEXT')) $false 'A picture that already carries text must be left alone.'
        Assert-Equal (& $isPlainPicture @('HTML Format', 'CF_DIB', 'PNG')) $false 'A picture copied from a web page must be left alone.'
        Assert-Equal (& $isPlainPicture @('CF_HDROP', 'CF_BITMAP')) $false 'Copied files must be left alone.'
        Assert-Equal (& $isPlainPicture @('CF_UNICODETEXT', 'CF_TEXT')) $false 'Plain text is not a picture.'
        Assert-Equal (& $isPlainPicture @()) $false 'An empty clipboard is not a picture.'
        Assert-Equal (& $isPlainPicture @('CF_BITMAP', 'ExcludeClipboardContentFromMonitorProcessing')) $false 'Data marked as private must be left alone.'
        Assert-Equal (& $isPlainPicture @('CF_BITMAP', 'Art::GVML ClipFormat')) $false 'Office objects must be left alone.'
        Assert-Equal ([TerminalBoard.ClipboardInspector]::HasPicture([string[]]@('CF_UNICODETEXT', 'CF_DIB'))) $true 'A picture next to text must still count as a picture (for the skip log).'
        Assert-Equal ([TerminalBoard.ClipboardInspector]::HasPicture([string[]]@('CF_UNICODETEXT', 'CF_TEXT'))) $false 'Text alone is not a picture.'

        $pictureDirectory = Join-Path $tempAppDataDirectory 'picture-store'
        $testPicture = New-Object System.Drawing.Bitmap 12, 8
        try {
            $savedPicturePath = [TerminalBoard.ImageStore]::Save($testPicture, $pictureDirectory)
        }
        finally {
            $testPicture.Dispose()
        }
        Assert-Equal (Test-Path -LiteralPath $savedPicturePath) $true 'Saving must write the PNG file.'
        Assert-Equal ((Split-Path -Leaf $savedPicturePath) -match '^img-\d{8}-\d{6}-\d{3}\.png$') $true 'Saved pictures must be named img-<timestamp>.png.'
        $roundTrip = [System.Drawing.Image]::FromFile($savedPicturePath)
        try {
            Assert-Equal "$($roundTrip.Width)x$($roundTrip.Height)" '12x8' 'The saved PNG must keep the picture size.'
        }
        finally {
            $roundTrip.Dispose()
        }

        $oldPicturePath = Join-Path $pictureDirectory 'img-19990101-000000-000.png'
        $unrelatedOldPath = Join-Path $pictureDirectory 'notes.png'
        foreach ($oldFile in @($oldPicturePath, $unrelatedOldPath)) {
            Set-Content -LiteralPath $oldFile -Value 'x'
            (Get-Item -LiteralPath $oldFile).LastWriteTime = (Get-Date).AddDays(-60)
        }
        $removedCount = [TerminalBoard.ImageStore]::Cleanup($pictureDirectory, [TimeSpan]::FromDays(30))
        Assert-Equal $removedCount 1 'Cleanup must remove exactly the old saved picture.'
        Assert-Equal (Test-Path -LiteralPath $oldPicturePath) $false 'An old saved picture must be deleted.'
        Assert-Equal (Test-Path -LiteralPath $savedPicturePath) $true 'A recent picture must be kept.'
        Assert-Equal (Test-Path -LiteralPath $unrelatedOldPath) $true 'Files the helper did not save must be kept.'

        Assert-Equal ([TerminalBoard.ImageStore]::ToClipboardText('C:\a\b.png')) 'C:\a\b.png ' 'Clipboard text must end with a space.'
        Assert-Equal ([TerminalBoard.ImageStore]::ToClipboardText('C:\My Files\b.png')) '"C:\My Files\b.png" ' 'A path with spaces must be quoted.'

        # The settings screen (C#) and `tb desk` (PowerShell) each build the board command; they must agree exactly.
        $parityFolder = (Get-Item -LiteralPath (New-Item -ItemType Directory -Path (Join-Path $tempAppDataDirectory 'parity folder') -Force).FullName).FullName
        $parityCases = @(
            @{ Count = 1; Layout = 'columns'; Panes = @('@shell') },
            @{ Count = 3; Layout = 'columns'; Panes = @('claude', '@shell', 'agy') },
            @{ Count = 5; Layout = 'rows'; Panes = @('claude', 'codex', 'agy', '@shell', 'npm run dev; echo "hi there"') },
            @{ Count = 12; Layout = 'columns'; Panes = @(1..12 | ForEach-Object { if ($_ % 3 -eq 0) { 'codex' } else { '@shell' } }) }
        )
        foreach ($parityCase in $parityCases) {
            $paneList = @($parityCase.Panes)
            while ($paneList.Count -lt 12) {
                $paneList += '@shell'
            }
            $paritySettingsPath = Join-Path $tempAppDataDirectory 'parity.json'
            $parityOutputPath = Join-Path $tempAppDataDirectory 'parity.txt'
            $paritySettings = @{ folder = $parityFolder; count = $parityCase.Count; layout = $parityCase.Layout; panes = $paneList }
            [System.IO.File]::WriteAllText($paritySettingsPath, ($paritySettings | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($true)))
            Start-Process -FilePath $helperExePath -ArgumentList '--print-board', "`"$paritySettingsPath`"", "`"$parityOutputPath`"" -Wait
            $fromExe = [System.IO.File]::ReadAllText($parityOutputPath)
            $fromScript = Open-TbDesk -Settings ([pscustomobject]@{ Folder = $parityFolder; Count = $parityCase.Count; Layout = $parityCase.Layout; Panes = $paneList }) -DryRun
            Assert-Equal ($fromExe -ceq $fromScript) $true "The settings screen and tb desk must build the same board command ($($parityCase.Count) panes, $($parityCase.Layout))."
        }

        # Draw the screen in a non-default colour theme, over a picture of the user's own, so both code paths run.
        Add-Type -AssemblyName System.Drawing
        $snapshotDataDirectory = Join-Path $tempAppDataDirectory 'snapshot-data'
        New-Item -ItemType Directory -Path $snapshotDataDirectory -Force | Out-Null
        $sampleBitmap = New-Object System.Drawing.Bitmap 400, 250
        $sampleGraphics = [System.Drawing.Graphics]::FromImage($sampleBitmap)
        $sampleGraphics.Clear([System.Drawing.Color]::FromArgb(255, 200, 120, 40))
        $sampleGraphics.Dispose()
        $sampleBitmap.Save((Join-Path $snapshotDataDirectory 'background.png'), [System.Drawing.Imaging.ImageFormat]::Png)
        $sampleBitmap.Dispose()
        [System.IO.File]::WriteAllText((Join-Path $snapshotDataDirectory 'desk.json'), '{"folder":"C:\\","count":4,"layout":"rows","theme":"burgundy","background":"background.png","panes":["claude","codex","agy","@shell"]}', (New-Object System.Text.UTF8Encoding($true)))
        $snapshotPath = Join-Path $tempAppDataDirectory 'screen.png'
        $snapshotRun = Start-Process -FilePath $helperExePath -ArgumentList '--desk-snapshot', "`"$snapshotPath`"", '--data-dir', "`"$snapshotDataDirectory`"" -Wait -PassThru
        Assert-Equal $snapshotRun.ExitCode 0 'The settings screen must build and draw without errors.'
        Assert-Equal ((Test-Path -LiteralPath $snapshotPath) -and ((Get-Item -LiteralPath $snapshotPath).Length -gt 20000)) $true 'The settings screen must draw a real picture.'

        # No settings at all: the default (gold) theme and its artwork.
        $defaultSnapshotPath = Join-Path $tempAppDataDirectory 'screen-default.png'
        $defaultSnapshotRun = Start-Process -FilePath $helperExePath -ArgumentList '--desk-snapshot', "`"$defaultSnapshotPath`"", '--data-dir', "`"$tempAppDataDirectory\no-settings-here`"" -Wait -PassThru
        Assert-Equal $defaultSnapshotRun.ExitCode 0 'The settings screen must draw in its default (gold) theme without errors.'
        Assert-Equal ((Test-Path -LiteralPath $defaultSnapshotPath) -and ((Get-Item -LiteralPath $defaultSnapshotPath).Length -gt 20000)) $true 'The default theme must draw a real picture.'
    }
}
finally {
    $env:LOCALAPPDATA = $savedLocalAppData
    Remove-Item -LiteralPath $tempAppDataDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'All Terminal Board tests passed.'
