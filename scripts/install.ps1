param(
  [string]$LogPath = "C:\ProgramData\PostInstall\postinstall.log"
)

Import-Module "$PSScriptRoot\modules\Utils.psm1" -Force
$Log = New-Logger -Path $LogPath
$Log.Write("=== Post-install start on $env:COMPUTERNAME (User: $env:USERNAME; Admin: $(Test-Admin)) ===")

# 1) Environment info
try {
  $sys  = Get-CimInstance Win32_ComputerSystem
  $bios = Get-CimInstance Win32_BIOS
  $csprod = Get-CimInstance Win32_ComputerSystemProduct
  $model = ($sys.Model, $csprod.Version | Where-Object { $_ }) -join " "
  $Log.Write("Vendor: $($sys.Manufacturer)  Model: $($sys.Model)  Serial: $($bios.SerialNumber)")
} catch { $Log.Write("Env read failed: $($_.Exception.Message)") }

# 2) Ensure winget (optional)
$HasWinget = Ensure-Winget -Log $Log

# 3) Install from simple winget list (optional)
$pkgList = Join-Path $PSScriptRoot "packages-winget.txt"
if (Test-Path -LiteralPath $pkgList) {
  $Log.Write("Processing packages-winget.txt...")
  Get-Content $pkgList | ForEach-Object {
    $id = $_.Trim()
    if (-not $id -or $id.StartsWith("#")) { return }
    if ($HasWinget) {
      Install-WingetPackage -Id $id -Exact -Log $Log | Out-Null
    } else {
      $Log.Write("Skipping winget package $id (winget not available).")
    }
  }
}

# 4) Arbitrary installers (optional via installers.json)
$instJson = Join-Path $PSScriptRoot "installers.json"
if (Test-Path -LiteralPath $instJson) {
  $Log.Write("Processing installers.json...")
  try {
    # -Raw avoids concatenating line-by-line strings
    $defs = Get-Content $instJson -Raw | ConvertFrom-Json
  } catch {
    $Log.Write("installers.json parse error: $($_.Exception.Message)")
    throw
  }

  $dlRoot = Join-Path $env:TEMP "postinstall_dl"
  New-Item -ItemType Directory -Force -Path $dlRoot | Out-Null

  foreach ($it in $defs.installers) {
    try {
      $name = $it.name
      $url  = $it.url
      $sha  = $it.sha256

      # PowerShell 5.1-safe null handling (no '??')
      $type = if ($it.PSObject.Properties.Name -contains 'type' -and $it.type) { "$($it.type)".ToLower() } else { "exe" }
      $args = if ($it.PSObject.Properties.Name -contains 'args' -and $it.args) { [string]$it.args } else { "" }

      # If 'type' omitted, infer from URL extension when possible
      if (-not $it.type -and $url -match '\.msi($|\?)') { $type = 'msi' }

      $out  = Join-Path $dlRoot (Split-Path $url -Leaf)

      $Log.Write("Installer: $name ($type) from $url")
      Invoke-Download -Url $url -OutFile $out -Log $Log | Out-Null

      if ($sha -and -not (Test-FileHashMatch -Path $out -Sha256 $sha -Quiet)) {
        throw "Hash mismatch for $name"
      }

      switch ($type) {
        'msi' { Install-MSI -Path $out -Arguments "/qn /norestart" -Log $Log | Out-Null }
        'exe' { Install-EXE -Path $out -Arguments ($args -as [string]) -Log $Log | Out-Null }
        'ps1' { Invoke-Ps1   -Path $out -Arguments @() -Log $Log | Out-Null }
        default { throw "Unknown installer type: $type" }
      }
    } catch {
      $Log.Write("Installer failed: $name - $($_.Exception.Message)")
    }
  }
}

# 5) Model-specific steps (example: MSI Stealth 14)
try {
  $modelScript = Join-Path $PSScriptRoot "models\MSI-Stealth-14.ps1"
  if ((($sys.Model) -like "*Stealth*14*") -and (Test-Path -LiteralPath $modelScript)) {
    $Log.Write("Applying model-specific steps for MSI Stealth 14...")
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $modelScript -LogPath $LogPath
  } else {
    $Log.Write("No model-specific script matched; running models\default.ps1 if present.")
    $def = Join-Path $PSScriptRoot "models\default.ps1"
    if (Test-Path -LiteralPath $def) {
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $def -LogPath $LogPath
    }
  }
} catch { $Log.Write("Model script failed: $($_.Exception.Message)") }

# 6) vMix -> prefer High Performance GPU for this user, Set vMix to use the High Performance GPU for the current user (HKCU)
try {
  $dxKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
  New-Item -Path $dxKey -Force | Out-Null

  # Get "Program Files (x86)" robustly
  $pf86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  if (-not $pf86) { $pf86 = "$env:SystemDrive\Program Files (x86)" }  # fallback

  $childPaths = @('vMix\vMix64.exe','vMix\vMix.exe')

  foreach ($child in $childPaths) {
    # IMPORTANT: pass a single string as -ChildPath
    $exe = Join-Path -Path $pf86 -ChildPath $child
    New-ItemProperty -Path $dxKey -Name $exe -PropertyType String -Value 'GpuPreference=2;' -Force | Out-Null
  }

  Write-Host "Set GPU prefs for vMix executables."
} catch {
  Write-Warning ("Failed to set GPU prefs: " + $_.Exception.Message)
}


$Log.Write("=== Qonnect-IT Post-install complete ===")
exit 0
