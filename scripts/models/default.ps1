# Try to use your Utils logger if available; otherwise fall back to a simple file log.
$log = $null
try {
  Import-Module "$PSScriptRoot\..\modules\Utils.psm1" -Force -ErrorAction Stop
  $log = New-Logger -Path $LogPath
} catch { }

function Write-Log([string]$msg) {
  if ($log -ne $null) {
    $log.Write($msg)
  } else {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $msg"
    try {
      $dir = Split-Path -Parent $LogPath
      if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
      Add-Content -LiteralPath $LogPath -Value $line
    } catch { }
    Write-Host $line
  }
}

Write-Log "[default] start (no-op placeholder)"
# --- Nothing to do here yet ---
Write-Log "[default] done"
