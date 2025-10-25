#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ProgressPreference = 'SilentlyContinue'

function New-Logger {
  param([Parameter(Mandatory=$true)][string]$Path)

  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType File -Force -Path $Path | Out-Null
  }

  # Build an object and attach a real ScriptMethod 'Write'
  $obj = New-Object PSObject
  $obj | Add-Member -NotePropertyName Path -NotePropertyValue $Path
  $obj | Add-Member -MemberType ScriptMethod -Name Write -Value {
    param([string]$Msg)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $Msg"
    Write-Host $line
    Add-Content -LiteralPath $this.Path -Value $line
  } -Force

  return $obj
}

function Test-Admin {
  $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
  $pr  = New-Object Security.Principal.WindowsPrincipal($id)
  return $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-Download {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$OutFile,
    [int]$TimeoutSec = 600,
    [int]$MaxRetries = 4,
    $Log
  )
  # Use TLS 1.2 for GitHub and most CDNs
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch {}

  for ($i = 1; $i -le $MaxRetries; $i++) {
    try {
      if ($Log) { $Log.Write("Downloading: $Url -> $OutFile (attempt $i/$MaxRetries)") }
      Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec
      if ((Get-Item -LiteralPath $OutFile).Length -lt 1024) { throw "Downloaded file too small" }
      return $OutFile
    } catch {
      if ($i -eq $MaxRetries) { throw }
      if ($Log) { $Log.Write("Download failed: $($_.Exception.Message). Retrying...") }
      Start-Sleep -Seconds ([Math]::Min(15, 2 * $i))
    }
  }
}

function Test-FileHashMatch {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [string]$Sha256,
    [switch]$Quiet
  )
  if (-not $Sha256) { return $true }
  $calc = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
  $ok = ($calc -eq $Sha256.ToUpperInvariant())
  if (-not $ok -and -not $Quiet) {
    Write-Warning "SHA256 mismatch for $Path (expected $Sha256, got $calc)"
  }
  return $ok
}

function Install-MSI {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$Path,
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
    [Parameter(Mandatory=$true)][string]$Path,
    [string]$Arguments = "/S",
    $Log
  )
  if ($Log) { $Log.Write("Installing EXE: $Path $Arguments") }
  # Unblock in case it was downloaded from the internet
  try { Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue } catch {}
  Start-Process -FilePath $Path -ArgumentList $Arguments -Wait
  return $LASTEXITCODE
}

function Invoke-Ps1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$Path,
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
    if ($Log) { $Log.Write("winget available") }
    try { winget source update | Out-Null } catch {}
    return $true
  } catch {
    if ($Log) { $Log.Write("winget not available; some installs may be skipped") }
    return $false
  }
}

function Install-WingetPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$Id,
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
