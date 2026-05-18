$ErrorActionPreference = "Stop"

$Model = if ($env:DEEPSEEK_MODEL) { $env:DEEPSEEK_MODEL } else { "deepseek-v4-pro" }
$DeepSeekBaseUrl = if ($env:DEEPSEEK_ANTHROPIC_BASE_URL) { $env:DEEPSEEK_ANTHROPIC_BASE_URL } else { "https://api.deepseek.com/anthropic" }
$SkipProviderConfig = ($env:SKIP_PROVIDER_CONFIG -eq "1") -or ($env:SKIP_MIMO_CONFIG -eq "1")

foreach ($arg in $args) {
  switch ($arg) {
    { $_ -in @("--skip-api-key", "--skip-mimo-config") } {
      $SkipProviderConfig = $true
      break
    }
    { $_ -in @("--help", "-h") } {
      Write-Host "Usage: install.ps1 [--skip-api-key]"
      Write-Host ""
      Write-Host "Environment:"
      Write-Host "  DEEPSEEK_API_KEY             DeepSeek API key"
      Write-Host "  DEEPSEEK_MODEL               Model name, default: deepseek-v4-pro"
      Write-Host "  DEEPSEEK_ANTHROPIC_BASE_URL  DeepSeek API base URL"
      Write-Host "  MIMO_API_KEY                 Optional Xiaomi MiMo API key for provider switching"
      Write-Host "  MIMO_ANTHROPIC_BASE_URL      API base URL; auto-detected for sk-/tp- keys if unset"
      Write-Host "  SKIP_PROVIDER_CONFIG=1       Install tools only; configure API later"
      exit 0
    }
  }
}

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return [ordered]@{}
  }

  try {
    return Get-Content -Raw -Path $Path | ConvertFrom-Json -AsHashtable
  }
  catch {
    $backup = "$Path.bak.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
    Copy-Item $Path $backup -Force
    Write-Warning "Existing JSON was invalid. Backed up to $backup"
    return [ordered]@{}
  }
}

function Write-JsonFile {
  param(
    [string]$Path,
    [object]$Value
  )

  $dir = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $json = $Value | ConvertTo-Json -Depth 20
  Set-Content -Path $Path -Encoding UTF8 -Value ($json + "`n")
}

function Test-MapKey {
  param(
    [object]$Map,
    [string]$Key
  )

  if ($Map -is [System.Collections.IDictionary]) {
    return $Map.Contains($Key)
  }

  return $null -ne $Map.PSObject.Properties[$Key]
}

function Get-MapValue {
  param(
    [object]$Map,
    [string]$Key
  )

  if ($Map -is [System.Collections.IDictionary]) {
    return $Map[$Key]
  }

  return $Map.PSObject.Properties[$Key].Value
}

function Set-MapValue {
  param(
    [object]$Map,
    [string]$Key,
    [object]$Value
  )

  if ($Map -is [System.Collections.IDictionary]) {
    $Map[$Key] = $Value
  }
  else {
    if ($Map.PSObject.Properties[$Key]) {
      $Map.PSObject.Properties[$Key].Value = $Value
    }
    else {
      $Map | Add-Member -NotePropertyName $Key -NotePropertyValue $Value
    }
  }
}

function Ensure-PathEntry {
  param([string]$PathToAdd)

  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if (-not $userPath) {
    $userPath = ""
  }

  $entries = $userPath -split ";" | Where-Object { $_ }
  if ($entries -notcontains $PathToAdd) {
    $newPath = if ($userPath) { "$userPath;$PathToAdd" } else { $PathToAdd }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$env:Path;$PathToAdd"
    Write-Host "Added to user PATH: $PathToAdd"
  }
}

function Ensure-ClaudePath {
  $candidateDirs = @()
  if ($HOME) {
    $candidateDirs += (Join-Path $HOME ".local\bin")
  }
  if ($env:LOCALAPPDATA) {
    $candidateDirs += (Join-Path $env:LOCALAPPDATA "bin")
  }

  foreach ($dir in $candidateDirs) {
    $claudeExe = Join-Path $dir "claude.exe"
    if (Test-Path $claudeExe) {
      Ensure-PathEntry $dir
      Write-Host "Claude Code command found at: $claudeExe"
      return
    }
  }

  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning "Claude Code was installed, but claude.exe was not found in common PATH locations. Restart PowerShell/CMD first; if it is still missing, add the Location printed by the official installer to your user PATH."
  }
}

function Find-ClaudeExePath {
  $candidateFiles = @()
  if ($HOME) {
    $candidateFiles += (Join-Path $HOME ".local\bin\claude.exe")
  }
  if ($env:LOCALAPPDATA) {
    $candidateFiles += (Join-Path $env:LOCALAPPDATA "bin\claude.exe")
  }

  foreach ($file in $candidateFiles) {
    if (Test-Path $file) {
      return $file
    }
  }

  $command = Get-Command claude.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  return $null
}

function Test-ClaudeCommand {
  try {
    $output = & claude --version 2>&1
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Claude Code is runnable: $output"
      return $true
    }
  }
  catch {
    Write-Warning "Claude command exists but did not run: $($_.Exception.Message)"
  }

  return $false
}

function Get-NpmClaudePackagePath {
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    return $null
  }

  try {
    $npmPrefix = (npm prefix -g).Trim()
    if (-not $npmPrefix) {
      return $null
    }

    return (Join-Path $npmPrefix "node_modules\@anthropic-ai\claude-code")
  }
  catch {
    return $null
  }
}

function Get-MimoBaseUrl {
  param([string]$Token)

  if ($env:MIMO_ANTHROPIC_BASE_URL) {
    return $env:MIMO_ANTHROPIC_BASE_URL
  }

  if ($Token -like "tp-*") {
    return "https://token-plan-cn.xiaomimimo.com/anthropic"
  }

  return "https://api.xiaomimimo.com/anthropic"
}

function Repair-ClaudeCodeNpmBinary {
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    return $false
  }

  if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    Write-Warning "Could not repair Claude Code npm binary because tar is not available."
    return $false
  }

  $packagePath = Get-NpmClaudePackagePath
  if (-not $packagePath -or -not (Test-Path $packagePath)) {
    return $false
  }

  $packageJsonPath = Join-Path $packagePath "package.json"
  if (-not (Test-Path $packageJsonPath)) {
    return $false
  }

  $packageJson = Get-Content -Raw -Path $packageJsonPath | ConvertFrom-Json
  $version = $packageJson.version
  if (-not $version) {
    return $false
  }

  $platformPackage = $null
  switch ("$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)") {
    "X64" { $platformPackage = "@anthropic-ai/claude-code-win32-x64" }
    "Arm64" { $platformPackage = "@anthropic-ai/claude-code-win32-arm64" }
    default {
      Write-Warning "Unsupported Windows architecture for Claude Code npm repair: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
      return $false
    }
  }

  $platformPath = Join-Path (Split-Path -Parent $packagePath) ($platformPackage -replace "^@anthropic-ai/", "")
  $platformExe = Join-Path $platformPath "claude.exe"
  $destExe = Join-Path $packagePath "bin\claude.exe"

  if ((Test-Path $platformExe) -and ((Get-Item $platformExe).Length -gt 100MB)) {
    Write-Host "Repairing Claude Code npm binary from installed platform package..."
    Copy-Item -Path $platformExe -Destination $destExe -Force
    return $true
  }

  Write-Host "Downloading Claude Code native Windows binary for npm repair..."
  $packageFileName = ($platformPackage -replace "^@anthropic-ai/", "")
  $tarballUrl = "https://registry.npmjs.org/$platformPackage/-/$packageFileName-$version.tgz"
  $tempRoot = Join-Path ([IO.Path]::GetTempPath()) "claude-code-native-$([Guid]::NewGuid().ToString('N'))"
  $tgzPath = Join-Path $tempRoot "$packageFileName-$version.tgz"
  $extractPath = Join-Path $tempRoot "extract"

  New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
  try {
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $tarballUrl -OutFile $tgzPath -TimeoutSec 1800
    tar -xzf $tgzPath -C $extractPath

    $downloadedExe = Join-Path $extractPath "package\claude.exe"
    if (-not (Test-Path $downloadedExe)) {
      throw "Downloaded package did not contain claude.exe."
    }

    if ((Get-Item $downloadedExe).Length -lt 100MB) {
      throw "Downloaded claude.exe is too small and may be incomplete."
    }

    Copy-Item -Path $downloadedExe -Destination $destExe -Force
    Write-Host "Repaired Claude Code npm binary: $destExe"
    return $true
  }
  catch {
    Write-Warning "Claude Code npm binary repair failed: $($_.Exception.Message)"
    return $false
  }
  finally {
    if (Test-Path $tempRoot) {
      Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Install-ClaudeCommandShim {
  $claudeExe = Find-ClaudeExePath
  if (-not $claudeExe) {
    Write-Warning "Could not create claude.cmd because claude.exe was not found."
    return
  }

  $installDir = Join-Path $HOME ".claude-provider"
  $cmdPath = Join-Path $installDir "claude.cmd"
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  Set-Content -Path $cmdPath -Encoding ASCII -Value "@echo off`r`n`"$claudeExe`" %*"
  Ensure-PathEntry $installDir
  Write-Host "Claude command shim installed to: $cmdPath"
}

function Install-ClaudeCodeNative {
  Write-Host "Installing or updating Claude Code with the official Windows installer..."
  try {
    Invoke-Expression (Invoke-RestMethod "https://claude.ai/install.ps1")
    Ensure-ClaudePath
    if ((Get-Command claude -ErrorAction SilentlyContinue) -and (Test-ClaudeCommand)) {
      return
    }
  }
  catch {
    Write-Warning "Official Claude Code installer failed: $($_.Exception.Message)"
  }

  Write-Host "Falling back to npm install for Claude Code..."
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "Could not install Claude Code automatically. The official installer failed, and npm is not installed."
  }

  npm install -g "@anthropic-ai/claude-code" --include=optional | Out-Host

  try {
    $npmPrefix = (npm prefix -g).Trim()
    if ($npmPrefix) {
      Ensure-PathEntry $npmPrefix
    }
  }
  catch {
    Write-Warning "Could not detect npm global prefix. If claude is not recognized, add your npm global bin directory to PATH."
  }

  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw "Claude Code npm install finished, but claude is still not recognized in this terminal."
  }

  if (-not (Test-ClaudeCommand)) {
    if ((Repair-ClaudeCodeNpmBinary) -and (Test-ClaudeCommand)) {
      return
    }

    throw "Claude Code is installed, but claude --version failed. Re-run this installer or check your network while downloading the Windows native binary."
  }
}

function Install-ProviderSwitcher {
  $installDir = Join-Path $HOME ".claude-provider"
  $scriptPath = Join-Path $installDir "switch-provider.ps1"
  $cmdPath = Join-Path $installDir "claude-provider.cmd"
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null

  if (Test-Path ".\switch-provider.ps1") {
    Copy-Item ".\switch-provider.ps1" $scriptPath -Force
  }
  else {
    $embeddedScript = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIg0KDQokUHJvdmlkZXJBcmcgPSBpZiAoJGFyZ3MuQ291bnQgLWd0IDApIHsgJGFyZ3NbMF0gfSBlbHNlIHsgIiIgfQokTW9kZWxBcmcgPSBpZiAoJGFyZ3MuQ291bnQgLWd0IDEpIHsgJGFyZ3NbMV0gfSBlbHNlIHsgIiIgfQokQ2xhdWRlSG9tZSA9IGlmICgkZW52OkNMQVVERV9IT01FKSB7ICRlbnY6Q0xBVURFX0hPTUUgfSBlbHNlIHsgJEhPTUUgfQokU2V0dGluZ3NGaWxlID0gSm9pbi1QYXRoICRDbGF1ZGVIb21lICIuY2xhdWRlXHNldHRpbmdzLmpzb24iCiRQcm92aWRlckZpbGUgPSBKb2luLVBhdGggJENsYXVkZUhvbWUgIi5jbGF1ZGVccHJvdmlkZXItc3dpdGNoLmpzb24iCg0KZnVuY3Rpb24gU2hvdy1Vc2FnZSB7DQogIFdyaXRlLUhvc3QgIlVzYWdlOiINCiAgV3JpdGUtSG9zdCAiICBjbGF1ZGUtcHJvdmlkZXIgbWltbyA8Zmxhc2h8cHJvfG9tbml8bW9kZWwtbmFtZT4iDQogIFdyaXRlLUhvc3QgIiAgY2xhdWRlLXByb3ZpZGVyIGRlZXBzZWVrIDxmbGFzaHxwcm98bW9kZWwtbmFtZT4iDQogIFdyaXRlLUhvc3QgIiINCiAgV3JpdGUtSG9zdCAiRW52aXJvbm1lbnQ6Ig0KICBXcml0ZS1Ib3N0ICIgIE1JTU9fQVBJX0tFWSAgICAgICAgICAgICAgICAgWGlhb21pIE1pTW8gQVBJIGtleSINCiAgV3JpdGUtSG9zdCAiICBERUVQU0VFS19BUElfS0VZICAgICAgICAgICAgIERlZXBTZWVrIEFQSSBrZXkiDQogIFdyaXRlLUhvc3QgIiAgTUlNT19BTlRIUk9QSUNfQkFTRV9VUkwgICAgICBPdmVycmlkZSBNaU1vIEFudGhyb3BpYyBiYXNlIFVSTCINCiAgV3JpdGUtSG9zdCAiICBERUVQU0VFS19BTlRIUk9QSUNfQkFTRV9VUkwgIERlZmF1bHQ6IGh0dHBzOi8vYXBpLmRlZXBzZWVrLmNvbS9hbnRocm9waWMiDQp9DQoNCmZ1bmN0aW9uIEdldC1NaW1vQmFzZVVybCB7DQogIHBhcmFtKFtzdHJpbmddJFRva2VuKQ0KDQogIGlmICgkVG9rZW4gLWxpa2UgInRwLSoiKSB7DQogICAgcmV0dXJuICJodHRwczovL3Rva2VuLXBsYW4tY24ueGlhb21pbWltby5jb20vYW50aHJvcGljIg0KICB9DQoNCiAgcmV0dXJuICJodHRwczovL2FwaS54aWFvbWltaW1vLmNvbS9hbnRocm9waWMiDQp9DQoNCnN3aXRjaCAoJFByb3ZpZGVyQXJnKSB7DQogIHsgJF8gLWluIEAoIm1pbW8iLCAieGlhb21pLW1pbW8iKSB9IHsNCiAgICAkUHJvdmlkZXIgPSAibWltbyINCiAgICAkVG9rZW4gPSBpZiAoJGVudjpNSU1PX0FQSV9LRVkpIHsgJGVudjpNSU1PX0FQSV9LRVkgfSBlbHNlIHsgIiIgfQ0KICAgICRCYXNlVXJsID0gaWYgKCRlbnY6TUlNT19BTlRIUk9QSUNfQkFTRV9VUkwpIHsgJGVudjpNSU1PX0FOVEhST1BJQ19CQVNFX1VSTCB9IGVsc2UgeyAiIiB9DQogICAgc3dpdGNoICgkTW9kZWxBcmcpIHsNCiAgICAgIHsgJF8gLWluIEAoImZsYXNoIiwgInYyLWZsYXNoIiwgIm1pbW8tdjItZmxhc2giLCAiIikgfSB7ICRNb2RlbCA9ICJtaW1vLXYyLWZsYXNoIjsgYnJlYWsgfQ0KICAgICAgeyAkXyAtaW4gQCgicHJvIiwgInYyLjUtcHJvIiwgIm1pbW8tdjIuNS1wcm8iLCAidjItcHJvIiwgIm1pbW8tdjItcHJvIikgfSB7ICRNb2RlbCA9ICJtaW1vLXYyLjUtcHJvIjsgYnJlYWsgfQ0KICAgICAgeyAkXyAtaW4gQCgib21uaSIsICJ2Mi41IiwgIm1pbW8tdjIuNSIsICJ2Mi1vbW5pIiwgIm1pbW8tdjItb21uaSIpIH0geyAkTW9kZWwgPSAibWltby12Mi41IjsgYnJlYWsgfQ0KICAgICAgeyAkXyAtaW4gQCgiLS1oZWxwIiwgIi1oIikgfSB7IFNob3ctVXNhZ2U7IGV4aXQgMCB9DQogICAgICBkZWZhdWx0IHsgJE1vZGVsID0gJE1vZGVsQXJnIH0NCiAgICB9DQogICAgYnJlYWsNCiAgfQ0KICB7ICRfIC1pbiBAKCJkZWVwc2VlayIsICJkcyIpIH0gew0KICAgICRQcm92aWRlciA9ICJkZWVwc2VlayINCiAgICAkQmFzZVVybCA9IGlmICgkZW52OkRFRVBTRUVLX0FOVEhST1BJQ19CQVNFX1VSTCkgeyAkZW52OkRFRVBTRUVLX0FOVEhST1BJQ19CQVNFX1VSTCB9IGVsc2UgeyAiaHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29tL2FudGhyb3BpYyIgfQ0KICAgICRUb2tlbiA9IGlmICgkZW52OkRFRVBTRUVLX0FQSV9LRVkpIHsgJGVudjpERUVQU0VFS19BUElfS0VZIH0gZWxzZSB7ICIiIH0NCiAgICBzd2l0Y2ggKCRNb2RlbEFyZykgew0KICAgICAgeyAkXyAtaW4gQCgiZmxhc2giLCAidjQtZmxhc2giLCAiZGVlcHNlZWstdjQtZmxhc2giLCAiIikgfSB7ICRNb2RlbCA9ICJkZWVwc2Vlay12NC1mbGFzaCI7IGJyZWFrIH0NCiAgICAgIHsgJF8gLWluIEAoInBybyIsICJ2NC1wcm8iLCAiZGVlcHNlZWstdjQtcHJvIikgfSB7ICRNb2RlbCA9ICJkZWVwc2Vlay12NC1wcm8iOyBicmVhayB9DQogICAgICB7ICRfIC1pbiBAKCItLWhlbHAiLCAiLWgiKSB9IHsgU2hvdy1Vc2FnZTsgZXhpdCAwIH0NCiAgICAgIGRlZmF1bHQgeyAkTW9kZWwgPSAkTW9kZWxBcmcgfQ0KICAgIH0NCiAgICBicmVhaw0KICB9DQogIHsgJF8gLWluIEAoIi0taGVscCIsICItaCIsICIiKSB9IHsNCiAgICBTaG93LVVzYWdlDQogICAgZXhpdCAwDQogIH0NCiAgZGVmYXVsdCB7DQogICAgdGhyb3cgIlVua25vd24gcHJvdmlkZXI6ICRQcm92aWRlckFyZy4gVXNlOiBtaW1vIG9yIGRlZXBzZWVrIg0KICB9DQp9DQoNCiRzZXR0aW5nc0RpciA9IFNwbGl0LVBhdGggLVBhcmVudCAkU2V0dGluZ3NGaWxlDQpOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1Gb3JjZSAtUGF0aCAkc2V0dGluZ3NEaXIgfCBPdXQtTnVsbA0KDQokZW52OkNMQVVERV9TRVRUSU5HU19GSUxFID0gJFNldHRpbmdzRmlsZQ0KJGVudjpDTEFVREVfUFJPVklERVJfRklMRSA9ICRQcm92aWRlckZpbGUNCiRlbnY6Q0xBVURFX1BST1ZJREVSX0VGRkVDVElWRSA9ICRQcm92aWRlcg0KJGVudjpDTEFVREVfTU9ERUxfRUZGRUNUSVZFID0gJE1vZGVsDQokZW52OkNMQVVERV9CQVNFX1VSTF9FRkZFQ1RJVkUgPSAkQmFzZVVybA0KJGVudjpDTEFVREVfVE9LRU5fRUZGRUNUSVZFID0gJFRva2VuDQoNCkAnDQpjb25zdCBmcyA9IHJlcXVpcmUoImZzIik7DQoNCmNvbnN0IHNldHRpbmdzRmlsZSA9IHByb2Nlc3MuZW52LkNMQVVERV9TRVRUSU5HU19GSUxFOw0KY29uc3QgcHJvdmlkZXJGaWxlID0gcHJvY2Vzcy5lbnYuQ0xBVURFX1BST1ZJREVSX0ZJTEU7DQpjb25zdCBwcm92aWRlciA9IHByb2Nlc3MuZW52LkNMQVVERV9QUk9WSURFUl9FRkZFQ1RJVkU7DQpjb25zdCBtb2RlbCA9IHByb2Nlc3MuZW52LkNMQVVERV9NT0RFTF9FRkZFQ1RJVkU7DQpjb25zdCBiYXNlVXJsRnJvbUVudiA9IHByb2Nlc3MuZW52LkNMQVVERV9CQVNFX1VSTF9FRkZFQ1RJVkUgfHwgIiI7DQpjb25zdCB0b2tlbkZyb21FbnYgPSBwcm9jZXNzLmVudi5DTEFVREVfVE9LRU5fRUZGRUNUSVZFIHx8ICIiOw0KDQpmdW5jdGlvbiByZWFkSnNvbihmaWxlKSB7DQogIGlmICghZnMuZXhpc3RzU3luYyhmaWxlKSkgcmV0dXJuIHt9Ow0KICB0cnkgew0KICAgIHJldHVybiBKU09OLnBhcnNlKGZzLnJlYWRGaWxlU3luYyhmaWxlLCAidXRmOCIpKTsNCiAgfSBjYXRjaCAoZXJyb3IpIHsNCiAgICBjb25zdCBiYWNrdXAgPSBgJHtmaWxlfS5iYWsuJHtEYXRlLm5vdygpfWA7DQogICAgZnMuY29weUZpbGVTeW5jKGZpbGUsIGJhY2t1cCk7DQogICAgY29uc29sZS53YXJuKGBFeGlzdGluZyBKU09OIHdhcyBpbnZhbGlkLiBCYWNrZWQgdXAgdG8gJHtiYWNrdXB9YCk7DQogICAgcmV0dXJuIHt9Ow0KICB9DQp9DQoNCmNvbnN0IHByb3ZpZGVyQ29uZmlnID0gcmVhZEpzb24ocHJvdmlkZXJGaWxlKTsNCnByb3ZpZGVyQ29uZmlnLnByb3ZpZGVycyA9IHByb3ZpZGVyQ29uZmlnLnByb3ZpZGVycyB8fCB7fTsNCmNvbnN0IGV4aXN0aW5nUHJvdmlkZXIgPSBwcm92aWRlckNvbmZpZy5wcm92aWRlcnNbcHJvdmlkZXJdIHx8IHt9Ow0KY29uc3QgdG9rZW4gPSB0b2tlbkZyb21FbnYgfHwgZXhpc3RpbmdQcm92aWRlci5hdXRoVG9rZW47DQpjb25zdCBiYXNlVXJsID0NCiAgYmFzZVVybEZyb21FbnYgfHwNCiAgKHByb3ZpZGVyID09PSAibWltbyIgJiYgU3RyaW5nKHRva2VuIHx8ICIiKS5zdGFydHNXaXRoKCJ0cC0iKQ0KICAgID8gImh0dHBzOi8vdG9rZW4tcGxhbi1jbi54aWFvbWltaW1vLmNvbS9hbnRocm9waWMiDQogICAgOiBwcm92aWRlciA9PT0gIm1pbW8iDQogICAgICA/ICJodHRwczovL2FwaS54aWFvbWltaW1vLmNvbS9hbnRocm9waWMiDQogICAgICA6ICJodHRwczovL2FwaS5kZWVwc2Vlay5jb20vYW50aHJvcGljIik7DQoNCnByb3ZpZGVyQ29uZmlnLnByb3ZpZGVyc1twcm92aWRlcl0gPSB7DQogIC4uLmV4aXN0aW5nUHJvdmlkZXIsDQogIGJhc2VVcmwsDQp9Ow0KDQppZiAodG9rZW5Gcm9tRW52KSB7DQogIHByb3ZpZGVyQ29uZmlnLnByb3ZpZGVyc1twcm92aWRlcl0uYXV0aFRva2VuID0gdG9rZW5Gcm9tRW52Ow0KfQ0KDQppZiAoIXRva2VuKSB7DQogIGNvbnN0IGVudk5hbWUgPSBwcm92aWRlciA9PT0gIm1pbW8iID8gIk1JTU9fQVBJX0tFWSIgOiAiREVFUFNFRUtfQVBJX0tFWSI7DQogIGNvbnNvbGUuZXJyb3IoYE1pc3NpbmcgQVBJIGtleSBmb3IgJHtwcm92aWRlcn0uIFJlLXJ1biB3aXRoICR7ZW52TmFtZX09Li4uIG9uY2UuYCk7DQogIHByb2Nlc3MuZXhpdCgxKTsNCn0NCg0KcHJvdmlkZXJDb25maWcuYWN0aXZlUHJvdmlkZXIgPSBwcm92aWRlcjsNCnByb3ZpZGVyQ29uZmlnLmFjdGl2ZU1vZGVsID0gbW9kZWw7DQpmcy53cml0ZUZpbGVTeW5jKHByb3ZpZGVyRmlsZSwgYCR7SlNPTi5zdHJpbmdpZnkocHJvdmlkZXJDb25maWcsIG51bGwsIDIpfVxuYCwgeyBtb2RlOiAwbzYwMCB9KTsNCg0KY29uc3Qgc2V0dGluZ3MgPSByZWFkSnNvbihzZXR0aW5nc0ZpbGUpOw0Kc2V0dGluZ3MuZW52ID0gewogIC4uLihzZXR0aW5ncy5lbnYgfHwge30pLAogIEFOVEhST1BJQ19CQVNFX1VSTDogYmFzZVVybCwKICBBTlRIUk9QSUNfQVBJX0tFWTogdG9rZW4sCiAgQU5USFJPUElDX01PREVMOiBtb2RlbCwKICBBTlRIUk9QSUNfREVGQVVMVF9IQUlLVV9NT0RFTDogbW9kZWwsCiAgQU5USFJPUElDX0RFRkFVTFRfU09OTkVUX01PREVMOiBtb2RlbCwKICBBTlRIUk9QSUNfREVGQVVMVF9PUFVTX01PREVMOiBtb2RlbCwKICBBTlRIUk9QSUNfREVGQVVMVF9IQUlLVV9NT0RFTF9OQU1FOiBgJHtwcm92aWRlcn06JHttb2RlbH1gLAogIEFOVEhST1BJQ19ERUZBVUxUX1NPTk5FVF9NT0RFTF9OQU1FOiBgJHtwcm92aWRlcn06JHttb2RlbH1gLAogIEFOVEhST1BJQ19ERUZBVUxUX09QVVNfTU9ERUxfTkFNRTogYCR7cHJvdmlkZXJ9OiR7bW9kZWx9YCwKICBBTlRIUk9QSUNfQ1VTVE9NX01PREVMX09QVElPTjogbW9kZWwsCiAgQU5USFJPUElDX0NVU1RPTV9NT0RFTF9PUFRJT05fTkFNRTogYCR7cHJvdmlkZXJ9OiR7bW9kZWx9YCwKICBBTlRIUk9QSUNfU01BTExfRkFTVF9NT0RFTDogbW9kZWwsCn07Cg0KaWYgKHNldHRpbmdzLmluY2x1ZGVDb0F1dGhvcmVkQnkgPT09IHVuZGVmaW5lZCkgew0KICBzZXR0aW5ncy5pbmNsdWRlQ29BdXRob3JlZEJ5ID0gZmFsc2U7DQp9DQoNCmZzLndyaXRlRmlsZVN5bmMoc2V0dGluZ3NGaWxlLCBgJHtKU09OLnN0cmluZ2lmeShzZXR0aW5ncywgbnVsbCwgMil9XG5gLCB7IG1vZGU6IDBvNjAwIH0pOw0KJ0AgfCBub2RlDQoNCldyaXRlLUhvc3QgIkNsYXVkZSBDb2RlIHByb3ZpZGVyIHNldCB0bzogJFByb3ZpZGVyIg0KV3JpdGUtSG9zdCAiQ2xhdWRlIENvZGUgbW9kZWwgc2V0IHRvOiAkTW9kZWwiDQpXcml0ZS1Ib3N0ICJSdW46IGNsYXVkZSINCg=="
    [System.IO.File]::WriteAllText($scriptPath, [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($embeddedScript)), [System.Text.Encoding]::UTF8)
  }

  if (Test-Path ".\claude-provider.cmd") {
    Copy-Item ".\claude-provider.cmd" $cmdPath -Force
  }
  else {
    Set-Content -Path $cmdPath -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0switch-provider.ps1`" %*"
  }

  Ensure-PathEntry $installDir
  Write-Host "Provider switcher installed to: $installDir"
}

function Install-ProviderKeySetter {
  $installDir = Join-Path $HOME ".claude-provider"
  $scriptPath = Join-Path $installDir "set-provider-key.ps1"
  $cmdPath = Join-Path $installDir "claude-provider-key.cmd"
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null

  if (Test-Path ".\set-provider-key.ps1") {
    Copy-Item ".\set-provider-key.ps1" $scriptPath -Force
  }
  else {
    $embeddedScript = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIg0KDQokUHJvdmlkZXJBcmcgPSBpZiAoJGFyZ3MuQ291bnQgLWd0IDApIHsgJGFyZ3NbMF0gfSBlbHNlIHsgIiIgfQokVG9rZW5BcmcgPSBpZiAoJGFyZ3MuQ291bnQgLWd0IDEpIHsgJGFyZ3NbMV0gfSBlbHNlIHsgIiIgfQokQ2xhdWRlSG9tZSA9IGlmICgkZW52OkNMQVVERV9IT01FKSB7ICRlbnY6Q0xBVURFX0hPTUUgfSBlbHNlIHsgJEhPTUUgfQokUHJvdmlkZXJGaWxlID0gSm9pbi1QYXRoICRDbGF1ZGVIb21lICIuY2xhdWRlXHByb3ZpZGVyLXN3aXRjaC5qc29uIgokU2V0dGluZ3NGaWxlID0gSm9pbi1QYXRoICRDbGF1ZGVIb21lICIuY2xhdWRlXHNldHRpbmdzLmpzb24iCg0KZnVuY3Rpb24gR2V0LU1pbW9CYXNlVXJsIHsNCiAgcGFyYW0oW3N0cmluZ10kVG9rZW4pDQoNCiAgaWYgKCRlbnY6TUlNT19BTlRIUk9QSUNfQkFTRV9VUkwpIHsNCiAgICByZXR1cm4gJGVudjpNSU1PX0FOVEhST1BJQ19CQVNFX1VSTA0KICB9DQoNCiAgaWYgKCRUb2tlbiAtbGlrZSAidHAtKiIpIHsNCiAgICByZXR1cm4gImh0dHBzOi8vdG9rZW4tcGxhbi1jbi54aWFvbWltaW1vLmNvbS9hbnRocm9waWMiDQogIH0NCg0KICByZXR1cm4gImh0dHBzOi8vYXBpLnhpYW9taW1pbW8uY29tL2FudGhyb3BpYyINCn0NCg0KZnVuY3Rpb24gU2hvdy1Vc2FnZSB7DQogIFdyaXRlLUhvc3QgIlVzYWdlOiINCiAgV3JpdGUtSG9zdCAiICBjbGF1ZGUtcHJvdmlkZXIta2V5IG1pbW8gW2FwaS1rZXldIg0KICBXcml0ZS1Ib3N0ICIgIGNsYXVkZS1wcm92aWRlci1rZXkgZGVlcHNlZWsgW2FwaS1rZXldIg0KICBXcml0ZS1Ib3N0ICIiDQogIFdyaXRlLUhvc3QgIkVudmlyb25tZW50OiINCiAgV3JpdGUtSG9zdCAiICBNSU1PX0FQSV9LRVkgICAgICBYaWFvbWkgTWlNbyBBUEkga2V5Ig0KICBXcml0ZS1Ib3N0ICIgIERFRVBTRUVLX0FQSV9LRVkgIERlZXBTZWVrIEFQSSBrZXkiDQp9DQoNCnN3aXRjaCAoJFByb3ZpZGVyQXJnKSB7DQogIHsgJF8gLWluIEAoIm1pbW8iLCAieGlhb21pLW1pbW8iKSB9IHsNCiAgICAkUHJvdmlkZXIgPSAibWltbyINCiAgICAkVG9rZW4gPSBpZiAoJFRva2VuQXJnKSB7ICRUb2tlbkFyZyB9IGVsc2VpZiAoJGVudjpNSU1PX0FQSV9LRVkpIHsgJGVudjpNSU1PX0FQSV9LRVkgfSBlbHNlIHsgIiIgfQ0KICAgIGJyZWFrDQogIH0NCiAgeyAkXyAtaW4gQCgiZGVlcHNlZWsiLCAiZHMiKSB9IHsNCiAgICAkUHJvdmlkZXIgPSAiZGVlcHNlZWsiDQogICAgJFRva2VuID0gaWYgKCRUb2tlbkFyZykgeyAkVG9rZW5BcmcgfSBlbHNlaWYgKCRlbnY6REVFUFNFRUtfQVBJX0tFWSkgeyAkZW52OkRFRVBTRUVLX0FQSV9LRVkgfSBlbHNlIHsgIiIgfQ0KICAgIGJyZWFrDQogIH0NCiAgeyAkXyAtaW4gQCgiLS1oZWxwIiwgIi1oIiwgIiIpIH0gew0KICAgIFNob3ctVXNhZ2UNCiAgICBleGl0IDANCiAgfQ0KICBkZWZhdWx0IHsNCiAgICB0aHJvdyAiVW5rbm93biBwcm92aWRlcjogJFByb3ZpZGVyQXJnLiBVc2U6IG1pbW8gb3IgZGVlcHNlZWsiDQogIH0NCn0NCg0KaWYgKC1ub3QgJFRva2VuKSB7DQogICRzZWN1cmVLZXkgPSBSZWFkLUhvc3QgIkVudGVyICRQcm92aWRlciBBUEkga2V5IiAtQXNTZWN1cmVTdHJpbmcNCiAgJGJzdHIgPSBbUnVudGltZS5JbnRlcm9wU2VydmljZXMuTWFyc2hhbF06OlNlY3VyZVN0cmluZ1RvQlNUUigkc2VjdXJlS2V5KQ0KICB0cnkgew0KICAgICRUb2tlbiA9IFtSdW50aW1lLkludGVyb3BTZXJ2aWNlcy5NYXJzaGFsXTo6UHRyVG9TdHJpbmdCU1RSKCRic3RyKQ0KICB9DQogIGZpbmFsbHkgew0KICAgIFtSdW50aW1lLkludGVyb3BTZXJ2aWNlcy5NYXJzaGFsXTo6WmVyb0ZyZWVCU1RSKCRic3RyKQ0KICB9DQp9DQoNCmlmICgtbm90ICRUb2tlbikgew0KICB0aHJvdyAiQVBJIGtleSBpcyByZXF1aXJlZC4iDQp9DQoNCiRzZXR0aW5nc0RpciA9IFNwbGl0LVBhdGggLVBhcmVudCAkUHJvdmlkZXJGaWxlDQpOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1Gb3JjZSAtUGF0aCAkc2V0dGluZ3NEaXIgfCBPdXQtTnVsbA0KDQokZW52OkNMQVVERV9LRVlfUFJPVklERVIgPSAkUHJvdmlkZXINCiRlbnY6Q0xBVURFX0tFWV9UT0tFTiA9ICRUb2tlbg0KJGVudjpDTEFVREVfS0VZX0JBU0VfVVJMID0gaWYgKCRQcm92aWRlciAtZXEgIm1pbW8iKSB7IEdldC1NaW1vQmFzZVVybCAkVG9rZW4gfSBlbHNlIHsgIiIgfQ0KJGVudjpDTEFVREVfUFJPVklERVJfRklMRSA9ICRQcm92aWRlckZpbGUNCiRlbnY6Q0xBVURFX1NFVFRJTkdTX0ZJTEUgPSAkU2V0dGluZ3NGaWxlDQoNCkAnDQpjb25zdCBmcyA9IHJlcXVpcmUoImZzIik7DQoNCmNvbnN0IHByb3ZpZGVyID0gcHJvY2Vzcy5lbnYuQ0xBVURFX0tFWV9QUk9WSURFUjsNCmNvbnN0IHRva2VuID0gcHJvY2Vzcy5lbnYuQ0xBVURFX0tFWV9UT0tFTjsNCmNvbnN0IGJhc2VVcmwgPSBwcm9jZXNzLmVudi5DTEFVREVfS0VZX0JBU0VfVVJMIHx8ICIiOw0KY29uc3QgcHJvdmlkZXJGaWxlID0gcHJvY2Vzcy5lbnYuQ0xBVURFX1BST1ZJREVSX0ZJTEU7DQpjb25zdCBzZXR0aW5nc0ZpbGUgPSBwcm9jZXNzLmVudi5DTEFVREVfU0VUVElOR1NfRklMRTsNCg0KZnVuY3Rpb24gcmVhZEpzb24oZmlsZSkgew0KICBpZiAoIWZzLmV4aXN0c1N5bmMoZmlsZSkpIHJldHVybiB7fTsNCiAgdHJ5IHsNCiAgICByZXR1cm4gSlNPTi5wYXJzZShmcy5yZWFkRmlsZVN5bmMoZmlsZSwgInV0ZjgiKSk7DQogIH0gY2F0Y2ggKGVycm9yKSB7DQogICAgY29uc3QgYmFja3VwID0gYCR7ZmlsZX0uYmFrLiR7RGF0ZS5ub3coKX1gOw0KICAgIGZzLmNvcHlGaWxlU3luYyhmaWxlLCBiYWNrdXApOw0KICAgIGNvbnNvbGUud2FybihgRXhpc3RpbmcgSlNPTiB3YXMgaW52YWxpZC4gQmFja2VkIHVwIHRvICR7YmFja3VwfWApOw0KICAgIHJldHVybiB7fTsNCiAgfQ0KfQ0KDQpjb25zdCBwcm92aWRlckNvbmZpZyA9IHJlYWRKc29uKHByb3ZpZGVyRmlsZSk7DQpwcm92aWRlckNvbmZpZy5wcm92aWRlcnMgPSBwcm92aWRlckNvbmZpZy5wcm92aWRlcnMgfHwge307DQpwcm92aWRlckNvbmZpZy5wcm92aWRlcnNbcHJvdmlkZXJdID0gew0KICAuLi4ocHJvdmlkZXJDb25maWcucHJvdmlkZXJzW3Byb3ZpZGVyXSB8fCB7fSksDQogIGF1dGhUb2tlbjogdG9rZW4sDQp9Ow0KaWYgKGJhc2VVcmwpIHsNCiAgcHJvdmlkZXJDb25maWcucHJvdmlkZXJzW3Byb3ZpZGVyXS5iYXNlVXJsID0gYmFzZVVybDsNCn0NCg0KZnMud3JpdGVGaWxlU3luYyhwcm92aWRlckZpbGUsIGAke0pTT04uc3RyaW5naWZ5KHByb3ZpZGVyQ29uZmlnLCBudWxsLCAyKX1cbmAsIHsgbW9kZTogMG82MDAgfSk7DQoNCmlmIChwcm92aWRlckNvbmZpZy5hY3RpdmVQcm92aWRlciA9PT0gcHJvdmlkZXIgJiYgZnMuZXhpc3RzU3luYyhzZXR0aW5nc0ZpbGUpKSB7DQogIGNvbnN0IHNldHRpbmdzID0gcmVhZEpzb24oc2V0dGluZ3NGaWxlKTsNCiAgc2V0dGluZ3MuZW52ID0gewogICAgLi4uKHNldHRpbmdzLmVudiB8fCB7fSksCiAgICBBTlRIUk9QSUNfQVBJX0tFWTogdG9rZW4sCiAgICAuLi4oYmFzZVVybCA/IHsgQU5USFJPUElDX0JBU0VfVVJMOiBiYXNlVXJsIH0gOiB7fSksCiAgfTsKICBkZWxldGUgc2V0dGluZ3MuZW52LkFOVEhST1BJQ19BVVRIX1RPS0VOOwogIGZzLndyaXRlRmlsZVN5bmMoc2V0dGluZ3NGaWxlLCBgJHtKU09OLnN0cmluZ2lmeShzZXR0aW5ncywgbnVsbCwgMil9XG5gLCB7IG1vZGU6IDBvNjAwIH0pOw0KfQ0KJ0AgfCBub2RlDQoNCldyaXRlLUhvc3QgIlNhdmVkIEFQSSBrZXkgZm9yIHByb3ZpZGVyOiAkUHJvdmlkZXIiDQpXcml0ZS1Ib3N0ICJJZiAkUHJvdmlkZXIgaXMgYWN0aXZlLCBDbGF1ZGUgQ29kZSBzZXR0aW5ncyB3ZXJlIHVwZGF0ZWQgdG9vLiINCg=="
    [System.IO.File]::WriteAllText($scriptPath, [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($embeddedScript)), [System.Text.Encoding]::UTF8)
  }

  if (Test-Path ".\claude-provider-key.cmd") {
    Copy-Item ".\claude-provider-key.cmd" $cmdPath -Force
  }
  else {
    Set-Content -Path $cmdPath -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0set-provider-key.ps1`" %*"
  }

  Ensure-PathEntry $installDir
  Write-Host "Provider API key setter installed to: $installDir"
}

function Install-MimoSwitcher {
  $installDir = Join-Path $HOME ".claude-mimo"
  $scriptPath = Join-Path $installDir "switch-mimo.ps1"
  $cmdPath = Join-Path $installDir "claude-mimo.cmd"
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null

  if (Test-Path ".\switch-mimo.ps1") {
    Copy-Item ".\switch-mimo.ps1" $scriptPath -Force
  }
  else {
    $embeddedScript = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIg0KDQokc2NyaXB0RGlyID0gU3BsaXQtUGF0aCAtUGFyZW50ICRNeUludm9jYXRpb24uTXlDb21tYW5kLlBhdGgNCiRwcm92aWRlckNtZCA9IEpvaW4tUGF0aCAkc2NyaXB0RGlyICJjbGF1ZGUtcHJvdmlkZXIuY21kIg0KJHByb3ZpZGVyUHMxID0gSm9pbi1QYXRoICRzY3JpcHREaXIgInN3aXRjaC1wcm92aWRlci5wczEiDQppZiAoVGVzdC1QYXRoICRwcm92aWRlckNtZCkgew0KICAmICRwcm92aWRlckNtZCBtaW1vIEBhcmdzDQogIGV4aXQgJExBU1RFWElUQ09ERQ0KfQ0KaWYgKFRlc3QtUGF0aCAkcHJvdmlkZXJQczEpIHsNCiAgJHNoZWxsID0gaWYgKEdldC1Db21tYW5kIHB3c2ggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpIHsgInB3c2giIH0gZWxzZSB7ICJwb3dlcnNoZWxsIiB9DQogICYgJHNoZWxsIC1Ob1Byb2ZpbGUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgJHByb3ZpZGVyUHMxIG1pbW8gQGFyZ3MNCiAgZXhpdCAkTEFTVEVYSVRDT0RFDQp9DQppZiAoR2V0LUNvbW1hbmQgY2xhdWRlLXByb3ZpZGVyIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSB7DQogICYgY2xhdWRlLXByb3ZpZGVyIG1pbW8gQGFyZ3MNCiAgZXhpdCAkTEFTVEVYSVRDT0RFDQp9DQoNCiRNb2RlbEFyZyA9IGlmICgkYXJncy5Db3VudCAtZ3QgMCkgeyAkYXJnc1swXSB9IGVsc2UgeyAiIiB9DQoNCmZ1bmN0aW9uIEdldC1NaW1vQmFzZVVybCB7DQogIGlmICgkZW52Ok1JTU9fQU5USFJPUElDX0JBU0VfVVJMKSB7DQogICAgcmV0dXJuICRlbnY6TUlNT19BTlRIUk9QSUNfQkFTRV9VUkwNCiAgfQ0KDQogIGlmICgkZW52Ok1JTU9fQVBJX0tFWSAtbGlrZSAidHAtKiIpIHsNCiAgICByZXR1cm4gImh0dHBzOi8vdG9rZW4tcGxhbi1jbi54aWFvbWltaW1vLmNvbS9hbnRocm9waWMiDQogIH0NCg0KICByZXR1cm4gImh0dHBzOi8vYXBpLnhpYW9taW1pbW8uY29tL2FudGhyb3BpYyINCn0NCg0KJEJhc2VVcmwgPSBHZXQtTWltb0Jhc2VVcmwNCg0Kc3dpdGNoICgkTW9kZWxBcmcpIHsNCiAgeyAkXyAtaW4gQCgiZmxhc2giLCAidjItZmxhc2giLCAibWltby12Mi1mbGFzaCIpIH0geyAkTW9kZWwgPSAibWltby12Mi1mbGFzaCI7IGJyZWFrIH0NCiAgeyAkXyAtaW4gQCgicHJvIiwgInYyLjUtcHJvIiwgIm1pbW8tdjIuNS1wcm8iLCAidjItcHJvIiwgIm1pbW8tdjItcHJvIikgfSB7ICRNb2RlbCA9ICJtaW1vLXYyLjUtcHJvIjsgYnJlYWsgfQ0KICB7ICRfIC1pbiBAKCJvbW5pIiwgInYyLjUiLCAibWltby12Mi41IiwgInYyLW9tbmkiLCAibWltby12Mi1vbW5pIikgfSB7ICRNb2RlbCA9ICJtaW1vLXYyLjUiOyBicmVhayB9DQogIHsgJF8gLWluIEAoIi0taGVscCIsICItaCIsICIiKSB9IHsNCiAgICBXcml0ZS1Ib3N0ICJVc2FnZTogLlxzd2l0Y2gtbWltby5wczEgPGZsYXNofHByb3xvbW5pfG1vZGVsLW5hbWU+Ig0KICAgIFdyaXRlLUhvc3QgIiINCiAgICBXcml0ZS1Ib3N0ICJTd2l0Y2ggQ2xhdWRlIENvZGUgdG8gYSBYaWFvbWkgTWlNbyBtb2RlbC4iDQogICAgZXhpdCAwDQogIH0NCiAgZGVmYXVsdCB7DQogICAgJE1vZGVsID0gJE1vZGVsQXJnDQogIH0NCn0NCg0KJGNsYXVkZUhvbWUgPSBpZiAoJGVudjpDTEFVREVfSE9NRSkgeyAkZW52OkNMQVVERV9IT01FIH0gZWxzZSB7ICRIT01FIH0KJHNldHRpbmdzRGlyID0gSm9pbi1QYXRoICRjbGF1ZGVIb21lICIuY2xhdWRlIgokc2V0dGluZ3NGaWxlID0gSm9pbi1QYXRoICRzZXR0aW5nc0RpciAic2V0dGluZ3MuanNvbiINCk5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLUZvcmNlIC1QYXRoICRzZXR0aW5nc0RpciB8IE91dC1OdWxsDQoNCiRlbnY6Q0xBVURFX1NFVFRJTkdTX0ZJTEUgPSAkc2V0dGluZ3NGaWxlDQokZW52Ok1JTU9fTU9ERUxfRUZGRUNUSVZFID0gJE1vZGVsDQokZW52Ok1JTU9fQkFTRV9VUkxfRUZGRUNUSVZFID0gJEJhc2VVcmwNCg0KQCcNCmNvbnN0IGZzID0gcmVxdWlyZSgiZnMiKTsNCg0KY29uc3Qgc2V0dGluZ3NGaWxlID0gcHJvY2Vzcy5lbnYuQ0xBVURFX1NFVFRJTkdTX0ZJTEU7DQpjb25zdCBtb2RlbCA9IHByb2Nlc3MuZW52Lk1JTU9fTU9ERUxfRUZGRUNUSVZFOw0KY29uc3QgYmFzZVVybCA9IHByb2Nlc3MuZW52Lk1JTU9fQkFTRV9VUkxfRUZGRUNUSVZFOw0KDQpsZXQgc2V0dGluZ3MgPSB7fTsNCmlmIChmcy5leGlzdHNTeW5jKHNldHRpbmdzRmlsZSkpIHsNCiAgdHJ5IHsNCiAgICBzZXR0aW5ncyA9IEpTT04ucGFyc2UoZnMucmVhZEZpbGVTeW5jKHNldHRpbmdzRmlsZSwgInV0ZjgiKSk7DQogIH0gY2F0Y2ggKGVycm9yKSB7DQogICAgY29uc3QgYmFja3VwID0gYCR7c2V0dGluZ3NGaWxlfS5iYWsuJHtEYXRlLm5vdygpfWA7DQogICAgZnMuY29weUZpbGVTeW5jKHNldHRpbmdzRmlsZSwgYmFja3VwKTsNCiAgICBjb25zb2xlLndhcm4oYEV4aXN0aW5nIHNldHRpbmdzIHdlcmUgaW52YWxpZCBKU09OLiBCYWNrZWQgdXAgdG8gJHtiYWNrdXB9YCk7DQogIH0NCn0NCg0Kc2V0dGluZ3MuZW52ID0gew0KICAuLi4oc2V0dGluZ3MuZW52IHx8IHt9KSwNCiAgQU5USFJPUElDX0JBU0VfVVJMOiBiYXNlVXJsLA0KICBBTlRIUk9QSUNfTU9ERUw6IG1vZGVsLA0KICBBTlRIUk9QSUNfREVGQVVMVF9IQUlLVV9NT0RFTDogbW9kZWwsDQogIEFOVEhST1BJQ19ERUZBVUxUX1NPTk5FVF9NT0RFTDogbW9kZWwsDQogIEFOVEhST1BJQ19ERUZBVUxUX09QVVNfTU9ERUw6IG1vZGVsLA0KfTsNCg0KaWYgKHNldHRpbmdzLmluY2x1ZGVDb0F1dGhvcmVkQnkgPT09IHVuZGVmaW5lZCkgew0KICBzZXR0aW5ncy5pbmNsdWRlQ29BdXRob3JlZEJ5ID0gZmFsc2U7DQp9DQoNCmZzLndyaXRlRmlsZVN5bmMoc2V0dGluZ3NGaWxlLCBgJHtKU09OLnN0cmluZ2lmeShzZXR0aW5ncywgbnVsbCwgMil9XG5gLCB7IG1vZGU6IDBvNjAwIH0pOw0KJ0AgfCBub2RlDQoNCldyaXRlLUhvc3QgIkNsYXVkZSBDb2RlIE1pTW8gbW9kZWwgc2V0IHRvOiAkTW9kZWwiDQpXcml0ZS1Ib3N0ICJSdW46IGNsYXVkZSINCg=="
    [System.IO.File]::WriteAllText($scriptPath, [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($embeddedScript)), [System.Text.Encoding]::UTF8)
  }

  if (Test-Path ".\claude-mimo.cmd") {
    Copy-Item ".\claude-mimo.cmd" $cmdPath -Force
  }
  else {
    Set-Content -Path $cmdPath -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0switch-mimo.ps1`" %*"
  }

  Ensure-PathEntry $installDir
  Write-Host "MiMo model switcher installed to: $installDir"
}

if (-not $SkipProviderConfig -and -not $env:DEEPSEEK_API_KEY) {
  $secureKey = Read-Host "Enter your DeepSeek API key" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
  try {
    $env:DEEPSEEK_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

if (-not $SkipProviderConfig -and -not $env:DEEPSEEK_API_KEY) {
  throw "DeepSeek API key is required."
}

$MimoBaseUrl = Get-MimoBaseUrl $env:MIMO_API_KEY

Install-ClaudeCodeNative

if (-not $SkipProviderConfig) {
  $settingsDir = Join-Path $HOME ".claude"
  $settingsFile = Join-Path $settingsDir "settings.json"
  $claudeJsonFile = Join-Path $HOME ".claude.json"
  $providerFile = Join-Path $settingsDir "provider-switch.json"

  $settings = Read-JsonFile $settingsFile
  if (-not (Test-MapKey $settings "env") -or -not (Get-MapValue $settings "env")) {
    Set-MapValue $settings "env" ([ordered]@{})
  }

  $settingsEnv = Get-MapValue $settings "env"
  Set-MapValue $settingsEnv "ANTHROPIC_BASE_URL" $DeepSeekBaseUrl
  Set-MapValue $settingsEnv "ANTHROPIC_API_KEY" $env:DEEPSEEK_API_KEY
  if (Test-MapKey $settingsEnv "ANTHROPIC_AUTH_TOKEN") {
    $settingsEnv.Remove("ANTHROPIC_AUTH_TOKEN") | Out-Null
  }
  Set-MapValue $settingsEnv "ANTHROPIC_MODEL" $Model
  Set-MapValue $settingsEnv "ANTHROPIC_DEFAULT_HAIKU_MODEL" $Model
  Set-MapValue $settingsEnv "ANTHROPIC_DEFAULT_SONNET_MODEL" $Model
  Set-MapValue $settingsEnv "ANTHROPIC_DEFAULT_OPUS_MODEL" $Model

  if (-not (Test-MapKey $settings "includeCoAuthoredBy")) {
    Set-MapValue $settings "includeCoAuthoredBy" $false
  }

  Write-JsonFile $settingsFile $settings

  $providerConfig = Read-JsonFile $providerFile
  if (-not (Test-MapKey $providerConfig "providers") -or -not (Get-MapValue $providerConfig "providers")) {
    Set-MapValue $providerConfig "providers" ([ordered]@{})
  }

  $providers = Get-MapValue $providerConfig "providers"
  Set-MapValue $providers "deepseek" ([ordered]@{
    baseUrl = $DeepSeekBaseUrl
    authToken = $env:DEEPSEEK_API_KEY
  })

  if ($env:MIMO_API_KEY) {
    Set-MapValue $providers "mimo" ([ordered]@{
      baseUrl = $MimoBaseUrl
      authToken = $env:MIMO_API_KEY
    })
  }

  Set-MapValue $providerConfig "activeProvider" "deepseek"
  Set-MapValue $providerConfig "activeModel" $Model
  Write-JsonFile $providerFile $providerConfig

  $claudeJson = Read-JsonFile $claudeJsonFile
  Set-MapValue $claudeJson "hasCompletedOnboarding" $true
  Write-JsonFile $claudeJsonFile $claudeJson

  Write-Host "Done. Claude Code is configured for DeepSeek model: $Model"
}
else {
  Write-Host "Skipped provider API configuration."
}

Install-MimoSwitcher
Install-ProviderSwitcher
Install-ProviderKeySetter
Install-ClaudeCommandShim

Write-Host ""
Write-Host "Restart CMD/PowerShell if new commands are not recognized."
Write-Host "Run: claude"
Write-Host "Switch provider/model with: claude-provider deepseek pro"
Write-Host "Switch provider/model with: claude-provider deepseek flash"
Write-Host "Switch provider/model with: claude-provider mimo pro"
