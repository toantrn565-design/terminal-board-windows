# Bound to a global Windows shortcut-key (see install.ps1). Runs with a
# hidden window, so feedback is a beep instead of console text: one short
# high beep on success, two low beeps if the clipboard had no image.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'TerminalBoard.psm1') -Force

try {
    Save-TbClipboardImage | Out-Null
    [console]::beep(1200, 150)
}
catch {
    [console]::beep(300, 250)
    [console]::beep(300, 250)
}
