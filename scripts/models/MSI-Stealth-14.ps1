param([string]$LogPath = "C:\ProgramData\PostInstall\postinstall.log")
Import-Module "$PSScriptRoot\..\modules\Utils.psm1" -Force
$Log = New-Logger -Path $LogPath
$Log.Write("[MSI-Stealth-14] start (no-op)")
# add model-specific steps here later
$Log.Write("[MSI-Stealth-14] done")
