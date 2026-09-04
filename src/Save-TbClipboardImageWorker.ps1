[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path
)

# Runs in its own -Sta process (see Save-TbClipboardImage). Clipboard image
# APIs throw outside a Single-Threaded Apartment, and pwsh.exe defaults to
# MTA, so this cannot run inline inside tb.ps1.
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) {
    exit 2
}

$image = [System.Windows.Forms.Clipboard]::GetImage()
try {
    $image.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $image.Dispose()
}

[System.Windows.Forms.Clipboard]::SetText($Path)
exit 0
