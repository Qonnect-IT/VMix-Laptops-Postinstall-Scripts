#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ProgressPreference = 'SilentlyContinue'

function New-Logger {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath (Split-Path -Parent $Path))) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType File -Force -Path $Path | Out-Null
  }
  return [pscustomobject]@{
    Path = $Path
    Write = {
      param([string]$Msg)
      $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
      $line = "[$ts] $Msg"
      Write-Host $line
      Add-Content -LiteralPath $this.Path -Value $line
    }
  }
}

function Test-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-Download {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$OutFile,
    [int]$TimeoutSec = 600,
    [int]$MaxRetries = 4,
    $Log
  )
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
  for ($i=1;$i -le $MaxRetries;$i++){
    try{
      if ($Log) { $Log.Write("Downloading: $Url → $OutFile (attempt $i/$MaxRetries)") }
      Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec
      if ((Get-Item $OutFile).Length -lt 1024) { throw "Downloaded file too small" }
      return $OutFile
    } catch {
      if ($i -eq $MaxRetries) { throw }
      if ($Log) { $Log.Write("Download failed: $($_.Exception.Message). Retrying…") }
      Start-Sleep -Seconds ([Math]::Min(15, 2*$i))
    }
  }
}

function Test-FileHashMatch {
  param([string]$Path,[string]$Sha256,[switch]$Quiet)
  if (-not $Sha256) { return $true }
  $calc = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
  $ok = ($calc -eq $Sha256.ToUpperInvariant())
  if (-not $ok -and -not $Quiet) { Write-Warning "SHA256 mismatch for $Path (expected $Sha256, got $calc)" }
  return $ok
}

function Install-MSI {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$Arguments = "/qn /norestart",
    $Log
  )
  if ($Log) { $Log.Write("Installing MSI: $Path $Arguments") }
  Start-Process "msiexec.exe" -ArgumentList "/i `"$Path`" $Arguments" -Wait
  return $LASTEXITCODE
}

function Install-EXE {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$Arguments = "/S",
    $Log
  )
  if ($Log) { $Log.Write("Installing EXE: $Path $Arguments") }
  Start-Process -FilePath $Path -ArgumentList $Arguments -Wait
  return $LASTEXITCODE
}

function Invoke-Ps1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [string[]]$Arguments = @(),
    $Log
  )
  if ($Log) { $Log.Write("Executing PS1: $Path $($Arguments -join ' ')") }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments
  return $LASTEXITCODE
}

function Ensure-Winget {
  param($Log)
  try {
    winget --version | Out-Null
    if ($Log) { $Log.Write("winget available: $(winget --version)") }
    # Refresh sources defensively
    try { winget source update | Out-Null } catch {}
    return $true
  } catch {
    if ($Log) { $Log.Write("winget not available; some installs may be skipped.") }
    return $false
  }
}

function Install-WingetPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Id,
    [string]$OverrideArgs = "",
    [switch]$Exact,
    $Log
  )
  $args = @("install","--id",$Id,"--silent","--disable-interactivity","--accept-package-agreements","--accept-source-agreements","--source","winget","--force")
  if ($Exact) { $args += "--exact" }
  if ($OverrideArgs) { $args += @("--override",$OverrideArgs) }
  if ($Log) { $Log.Write("winget install: $($args -join ' ')") }
  winget @args
  return $LASTEXITCODE
}

Export-ModuleMember -Function *-*
