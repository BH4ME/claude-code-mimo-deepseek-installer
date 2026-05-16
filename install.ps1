$ErrorActionPreference = "Stop"

$Model = if ($env:MIMO_MODEL) { $env:MIMO_MODEL } else { "mimo-v2.5-pro" }
$DeepSeekBaseUrl = if ($env:DEEPSEEK_ANTHROPIC_BASE_URL) { $env:DEEPSEEK_ANTHROPIC_BASE_URL } else { "https://api.deepseek.com/anthropic" }
$SkipMimoConfig = $env:SKIP_MIMO_CONFIG -eq "1"

foreach ($arg in $args) {
  switch ($arg) {
    { $_ -in @("--skip-api-key", "--skip-mimo-config") } {
      $SkipMimoConfig = $true
      break
    }
    { $_ -in @("--help", "-h") } {
      Write-Host "Usage: install.ps1 [--skip-api-key]"
      Write-Host ""
      Write-Host "Environment:"
      Write-Host "  MIMO_API_KEY                 Xiaomi MiMo API key"
      Write-Host "  MIMO_MODEL                   Model name, default: mimo-v2.5-pro"
      Write-Host "  MIMO_ANTHROPIC_BASE_URL      API base URL; auto-detected for sk-/tp- keys if unset"
      Write-Host "  DEEPSEEK_API_KEY             Optional DeepSeek API key for provider switching"
      Write-Host "  DEEPSEEK_ANTHROPIC_BASE_URL  DeepSeek API base URL"
      Write-Host "  SKIP_MIMO_CONFIG=1           Install tools only; configure API later"
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
    $embeddedScript = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIg0KDQokUHJvdmlkZXJBcmcgPSBpZiAoJGFyZ3MuQ291bnQgLWd0IDApIHsgJGFyZ3NbMF0gfSBlbHNlIHsgIiIgfQ0KJE1vZGVsQXJnID0gaWYgKCRhcmdzLkNvdW50IC1ndCAxKSB7ICRhcmdzWzFdIH0gZWxzZSB7ICIiIH0NCiRTZXR0aW5nc0ZpbGUgPSBKb2luLVBhdGggJEhPTUUgIi5jbGF1ZGVcc2V0dGluZ3MuanNvbiINCiRQcm92aWRlckZpbGUgPSBKb2luLVBhdGggJEhPTUUgIi5jbGF1ZGVccHJvdmlkZXItc3dpdGNoLmpzb24iDQoNCmZ1bmN0aW9uIFNob3ctVXNhZ2Ugew0KICBXcml0ZS1Ib3N0ICJVc2FnZToiDQogIFdyaXRlLUhvc3QgIiAgY2xhdWRlLXByb3ZpZGVyIG1pbW8gPGZsYXNofHByb3xvbW5pfG1vZGVsLW5hbWU+Ig0KICBXcml0ZS1Ib3N0ICIgIGNsYXVkZS1wcm92aWRlciBkZWVwc2VlayA8Zmxhc2h8cHJvfG1vZGVsLW5hbWU+Ig0KICBXcml0ZS1Ib3N0ICIiDQogIFdyaXRlLUhvc3QgIkVudmlyb25tZW50OiINCiAgV3JpdGUtSG9zdCAiICBNSU1PX0FQSV9LRVkgICAgICAgICAgICAgICAgIFhpYW9taSBNaU1vIEFQSSBrZXkiDQogIFdyaXRlLUhvc3QgIiAgREVFUFNFRUtfQVBJX0tFWSAgICAgICAgICAgICBEZWVwU2VlayBBUEkga2V5Ig0KICBXcml0ZS1Ib3N0ICIgIE1JTU9fQU5USFJPUElDX0JBU0VfVVJMICAgICAgT3ZlcnJpZGUgTWlNbyBBbnRocm9waWMgYmFzZSBVUkwiDQogIFdyaXRlLUhvc3QgIiAgREVFUFNFRUtfQU5USFJPUElDX0JBU0VfVVJMICBEZWZhdWx0OiBodHRwczovL2FwaS5kZWVwc2Vlay5jb20vYW50aHJvcGljIg0KfQ0KDQpmdW5jdGlvbiBHZXQtTWltb0Jhc2VVcmwgew0KICBwYXJhbShbc3RyaW5nXSRUb2tlbikNCg0KICBpZiAoJFRva2VuIC1saWtlICJ0cC0qIikgew0KICAgIHJldHVybiAiaHR0cHM6Ly90b2tlbi1wbGFuLWNuLnhpYW9taW1pbW8uY29tL2FudGhyb3BpYyINCiAgfQ0KDQogIHJldHVybiAiaHR0cHM6Ly9hcGkueGlhb21pbWltby5jb20vYW50aHJvcGljIg0KfQ0KDQpzd2l0Y2ggKCRQcm92aWRlckFyZykgew0KICB7ICRfIC1pbiBAKCJtaW1vIiwgInhpYW9taS1taW1vIikgfSB7DQogICAgJFByb3ZpZGVyID0gIm1pbW8iDQogICAgJFRva2VuID0gaWYgKCRlbnY6TUlNT19BUElfS0VZKSB7ICRlbnY6TUlNT19BUElfS0VZIH0gZWxzZSB7ICIiIH0NCiAgICAkQmFzZVVybCA9IGlmICgkZW52Ok1JTU9fQU5USFJPUElDX0JBU0VfVVJMKSB7ICRlbnY6TUlNT19BTlRIUk9QSUNfQkFTRV9VUkwgfSBlbHNlIHsgIiIgfQ0KICAgIHN3aXRjaCAoJE1vZGVsQXJnKSB7DQogICAgICB7ICRfIC1pbiBAKCJmbGFzaCIsICJ2Mi1mbGFzaCIsICJtaW1vLXYyLWZsYXNoIiwgIiIpIH0geyAkTW9kZWwgPSAibWltby12Mi1mbGFzaCI7IGJyZWFrIH0NCiAgICAgIHsgJF8gLWluIEAoInBybyIsICJ2Mi41LXBybyIsICJtaW1vLXYyLjUtcHJvIiwgInYyLXBybyIsICJtaW1vLXYyLXBybyIpIH0geyAkTW9kZWwgPSAibWltby12Mi41LXBybyI7IGJyZWFrIH0NCiAgICAgIHsgJF8gLWluIEAoIm9tbmkiLCAidjIuNSIsICJtaW1vLXYyLjUiLCAidjItb21uaSIsICJtaW1vLXYyLW9tbmkiKSB9IHsgJE1vZGVsID0gIm1pbW8tdjIuNSI7IGJyZWFrIH0NCiAgICAgIHsgJF8gLWluIEAoIi0taGVscCIsICItaCIpIH0geyBTaG93LVVzYWdlOyBleGl0IDAgfQ0KICAgICAgZGVmYXVsdCB7ICRNb2RlbCA9ICRNb2RlbEFyZyB9DQogICAgfQ0KICAgIGJyZWFrDQogIH0NCiAgeyAkXyAtaW4gQCgiZGVlcHNlZWsiLCAiZHMiKSB9IHsNCiAgICAkUHJvdmlkZXIgPSAiZGVlcHNlZWsiDQogICAgJEJhc2VVcmwgPSBpZiAoJGVudjpERUVQU0VFS19BTlRIUk9QSUNfQkFTRV9VUkwpIHsgJGVudjpERUVQU0VFS19BTlRIUk9QSUNfQkFTRV9VUkwgfSBlbHNlIHsgImh0dHBzOi8vYXBpLmRlZXBzZWVrLmNvbS9hbnRocm9waWMiIH0NCiAgICAkVG9rZW4gPSBpZiAoJGVudjpERUVQU0VFS19BUElfS0VZKSB7ICRlbnY6REVFUFNFRUtfQVBJX0tFWSB9IGVsc2UgeyAiIiB9DQogICAgc3dpdGNoICgkTW9kZWxBcmcpIHsNCiAgICAgIHsgJF8gLWluIEAoImZsYXNoIiwgInY0LWZsYXNoIiwgImRlZXBzZWVrLXY0LWZsYXNoIiwgIiIpIH0geyAkTW9kZWwgPSAiZGVlcHNlZWstdjQtZmxhc2giOyBicmVhayB9DQogICAgICB7ICRfIC1pbiBAKCJwcm8iLCAidjQtcHJvIiwgImRlZXBzZWVrLXY0LXBybyIpIH0geyAkTW9kZWwgPSAiZGVlcHNlZWstdjQtcHJvIjsgYnJlYWsgfQ0KICAgICAgeyAkXyAtaW4gQCgiLS1oZWxwIiwgIi1oIikgfSB7IFNob3ctVXNhZ2U7IGV4aXQgMCB9DQogICAgICBkZWZhdWx0IHsgJE1vZGVsID0gJE1vZGVsQXJnIH0NCiAgICB9DQogICAgYnJlYWsNCiAgfQ0KICB7ICRfIC1pbiBAKCItLWhlbHAiLCAiLWgiLCAiIikgfSB7DQogICAgU2hvdy1Vc2FnZQ0KICAgIGV4aXQgMA0KICB9DQogIGRlZmF1bHQgew0KICAgIHRocm93ICJVbmtub3duIHByb3ZpZGVyOiAkUHJvdmlkZXJBcmcuIFVzZTogbWltbyBvciBkZWVwc2VlayINCiAgfQ0KfQ0KDQokc2V0dGluZ3NEaXIgPSBTcGxpdC1QYXRoIC1QYXJlbnQgJFNldHRpbmdzRmlsZQ0KTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtRm9yY2UgLVBhdGggJHNldHRpbmdzRGlyIHwgT3V0LU51bGwNCg0KJGVudjpDTEFVREVfU0VUVElOR1NfRklMRSA9ICRTZXR0aW5nc0ZpbGUNCiRlbnY6Q0xBVURFX1BST1ZJREVSX0ZJTEUgPSAkUHJvdmlkZXJGaWxlDQokZW52OkNMQVVERV9QUk9WSURFUl9FRkZFQ1RJVkUgPSAkUHJvdmlkZXINCiRlbnY6Q0xBVURFX01PREVMX0VGRkVDVElWRSA9ICRNb2RlbA0KJGVudjpDTEFVREVfQkFTRV9VUkxfRUZGRUNUSVZFID0gJEJhc2VVcmwNCiRlbnY6Q0xBVURFX1RPS0VOX0VGRkVDVElWRSA9ICRUb2tlbg0KDQpAJw0KY29uc3QgZnMgPSByZXF1aXJlKCJmcyIpOw0KDQpjb25zdCBzZXR0aW5nc0ZpbGUgPSBwcm9jZXNzLmVudi5DTEFVREVfU0VUVElOR1NfRklMRTsNCmNvbnN0IHByb3ZpZGVyRmlsZSA9IHByb2Nlc3MuZW52LkNMQVVERV9QUk9WSURFUl9GSUxFOw0KY29uc3QgcHJvdmlkZXIgPSBwcm9jZXNzLmVudi5DTEFVREVfUFJPVklERVJfRUZGRUNUSVZFOw0KY29uc3QgbW9kZWwgPSBwcm9jZXNzLmVudi5DTEFVREVfTU9ERUxfRUZGRUNUSVZFOw0KY29uc3QgYmFzZVVybEZyb21FbnYgPSBwcm9jZXNzLmVudi5DTEFVREVfQkFTRV9VUkxfRUZGRUNUSVZFIHx8ICIiOw0KY29uc3QgdG9rZW5Gcm9tRW52ID0gcHJvY2Vzcy5lbnYuQ0xBVURFX1RPS0VOX0VGRkVDVElWRSB8fCAiIjsNCg0KZnVuY3Rpb24gcmVhZEpzb24oZmlsZSkgew0KICBpZiAoIWZzLmV4aXN0c1N5bmMoZmlsZSkpIHJldHVybiB7fTsNCiAgdHJ5IHsNCiAgICByZXR1cm4gSlNPTi5wYXJzZShmcy5yZWFkRmlsZVN5bmMoZmlsZSwgInV0ZjgiKSk7DQogIH0gY2F0Y2ggKGVycm9yKSB7DQogICAgY29uc3QgYmFja3VwID0gYCR7ZmlsZX0uYmFrLiR7RGF0ZS5ub3coKX1gOw0KICAgIGZzLmNvcHlGaWxlU3luYyhmaWxlLCBiYWNrdXApOw0KICAgIGNvbnNvbGUud2FybihgRXhpc3RpbmcgSlNPTiB3YXMgaW52YWxpZC4gQmFja2VkIHVwIHRvICR7YmFja3VwfWApOw0KICAgIHJldHVybiB7fTsNCiAgfQ0KfQ0KDQpjb25zdCBwcm92aWRlckNvbmZpZyA9IHJlYWRKc29uKHByb3ZpZGVyRmlsZSk7DQpwcm92aWRlckNvbmZpZy5wcm92aWRlcnMgPSBwcm92aWRlckNvbmZpZy5wcm92aWRlcnMgfHwge307DQpjb25zdCBleGlzdGluZ1Byb3ZpZGVyID0gcHJvdmlkZXJDb25maWcucHJvdmlkZXJzW3Byb3ZpZGVyXSB8fCB7fTsNCmNvbnN0IHRva2VuID0gdG9rZW5Gcm9tRW52IHx8IGV4aXN0aW5nUHJvdmlkZXIuYXV0aFRva2VuOw0KY29uc3QgYmFzZVVybCA9DQogIGJhc2VVcmxGcm9tRW52IHx8DQogIChwcm92aWRlciA9PT0gIm1pbW8iICYmIFN0cmluZyh0b2tlbiB8fCAiIikuc3RhcnRzV2l0aCgidHAtIikNCiAgICA/ICJodHRwczovL3Rva2VuLXBsYW4tY24ueGlhb21pbWltby5jb20vYW50aHJvcGljIg0KICAgIDogcHJvdmlkZXIgPT09ICJtaW1vIg0KICAgICAgPyAiaHR0cHM6Ly9hcGkueGlhb21pbWltby5jb20vYW50aHJvcGljIg0KICAgICAgOiAiaHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29tL2FudGhyb3BpYyIpOw0KDQpwcm92aWRlckNvbmZpZy5wcm92aWRlcnNbcHJvdmlkZXJdID0gew0KICAuLi5leGlzdGluZ1Byb3ZpZGVyLA0KICBiYXNlVXJsLA0KfTsNCg0KaWYgKHRva2VuRnJvbUVudikgew0KICBwcm92aWRlckNvbmZpZy5wcm92aWRlcnNbcHJvdmlkZXJdLmF1dGhUb2tlbiA9IHRva2VuRnJvbUVudjsNCn0NCg0KaWYgKCF0b2tlbikgew0KICBjb25zdCBlbnZOYW1lID0gcHJvdmlkZXIgPT09ICJtaW1vIiA/ICJNSU1PX0FQSV9LRVkiIDogIkRFRVBTRUVLX0FQSV9LRVkiOw0KICBjb25zb2xlLmVycm9yKGBNaXNzaW5nIEFQSSBrZXkgZm9yICR7cHJvdmlkZXJ9LiBSZS1ydW4gd2l0aCAke2Vudk5hbWV9PS4uLiBvbmNlLmApOw0KICBwcm9jZXNzLmV4aXQoMSk7DQp9DQoNCnByb3ZpZGVyQ29uZmlnLmFjdGl2ZVByb3ZpZGVyID0gcHJvdmlkZXI7DQpwcm92aWRlckNvbmZpZy5hY3RpdmVNb2RlbCA9IG1vZGVsOw0KZnMud3JpdGVGaWxlU3luYyhwcm92aWRlckZpbGUsIGAke0pTT04uc3RyaW5naWZ5KHByb3ZpZGVyQ29uZmlnLCBudWxsLCAyKX1cbmAsIHsgbW9kZTogMG82MDAgfSk7DQoNCmNvbnN0IHNldHRpbmdzID0gcmVhZEpzb24oc2V0dGluZ3NGaWxlKTsNCnNldHRpbmdzLmVudiA9IHsNCiAgLi4uKHNldHRpbmdzLmVudiB8fCB7fSksDQogIEFOVEhST1BJQ19CQVNFX1VSTDogYmFzZVVybCwNCiAgQU5USFJPUElDX0FVVEhfVE9LRU46IHRva2VuLA0KICBBTlRIUk9QSUNfTU9ERUw6IG1vZGVsLA0KICBBTlRIUk9QSUNfREVGQVVMVF9IQUlLVV9NT0RFTDogbW9kZWwsDQogIEFOVEhST1BJQ19ERUZBVUxUX1NPTk5FVF9NT0RFTDogbW9kZWwsDQogIEFOVEhST1BJQ19ERUZBVUxUX09QVVNfTU9ERUw6IG1vZGVsLA0KfTsNCg0KaWYgKHNldHRpbmdzLmluY2x1ZGVDb0F1dGhvcmVkQnkgPT09IHVuZGVmaW5lZCkgew0KICBzZXR0aW5ncy5pbmNsdWRlQ29BdXRob3JlZEJ5ID0gZmFsc2U7DQp9DQoNCmZzLndyaXRlRmlsZVN5bmMoc2V0dGluZ3NGaWxlLCBgJHtKU09OLnN0cmluZ2lmeShzZXR0aW5ncywgbnVsbCwgMil9XG5gLCB7IG1vZGU6IDBvNjAwIH0pOw0KJ0AgfCBub2RlDQoNCldyaXRlLUhvc3QgIkNsYXVkZSBDb2RlIHByb3ZpZGVyIHNldCB0bzogJFByb3ZpZGVyIg0KV3JpdGUtSG9zdCAiQ2xhdWRlIENvZGUgbW9kZWwgc2V0IHRvOiAkTW9kZWwiDQpXcml0ZS1Ib3N0ICJSdW46IGNsYXVkZSINCg=="
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
    $embeddedScript = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIg0KDQokUHJvdmlkZXJBcmcgPSBpZiAoJGFyZ3MuQ291bnQgLWd0IDApIHsgJGFyZ3NbMF0gfSBlbHNlIHsgIiIgfQ0KJFRva2VuQXJnID0gaWYgKCRhcmdzLkNvdW50IC1ndCAxKSB7ICRhcmdzWzFdIH0gZWxzZSB7ICIiIH0NCiRQcm92aWRlckZpbGUgPSBKb2luLVBhdGggJEhPTUUgIi5jbGF1ZGVccHJvdmlkZXItc3dpdGNoLmpzb24iDQokU2V0dGluZ3NGaWxlID0gSm9pbi1QYXRoICRIT01FICIuY2xhdWRlXHNldHRpbmdzLmpzb24iDQoNCmZ1bmN0aW9uIEdldC1NaW1vQmFzZVVybCB7DQogIHBhcmFtKFtzdHJpbmddJFRva2VuKQ0KDQogIGlmICgkZW52Ok1JTU9fQU5USFJPUElDX0JBU0VfVVJMKSB7DQogICAgcmV0dXJuICRlbnY6TUlNT19BTlRIUk9QSUNfQkFTRV9VUkwNCiAgfQ0KDQogIGlmICgkVG9rZW4gLWxpa2UgInRwLSoiKSB7DQogICAgcmV0dXJuICJodHRwczovL3Rva2VuLXBsYW4tY24ueGlhb21pbWltby5jb20vYW50aHJvcGljIg0KICB9DQoNCiAgcmV0dXJuICJodHRwczovL2FwaS54aWFvbWltaW1vLmNvbS9hbnRocm9waWMiDQp9DQoNCmZ1bmN0aW9uIFNob3ctVXNhZ2Ugew0KICBXcml0ZS1Ib3N0ICJVc2FnZToiDQogIFdyaXRlLUhvc3QgIiAgY2xhdWRlLXByb3ZpZGVyLWtleSBtaW1vIFthcGkta2V5XSINCiAgV3JpdGUtSG9zdCAiICBjbGF1ZGUtcHJvdmlkZXIta2V5IGRlZXBzZWVrIFthcGkta2V5XSINCiAgV3JpdGUtSG9zdCAiIg0KICBXcml0ZS1Ib3N0ICJFbnZpcm9ubWVudDoiDQogIFdyaXRlLUhvc3QgIiAgTUlNT19BUElfS0VZICAgICAgWGlhb21pIE1pTW8gQVBJIGtleSINCiAgV3JpdGUtSG9zdCAiICBERUVQU0VFS19BUElfS0VZICBEZWVwU2VlayBBUEkga2V5Ig0KfQ0KDQpzd2l0Y2ggKCRQcm92aWRlckFyZykgew0KICB7ICRfIC1pbiBAKCJtaW1vIiwgInhpYW9taS1taW1vIikgfSB7DQogICAgJFByb3ZpZGVyID0gIm1pbW8iDQogICAgJFRva2VuID0gaWYgKCRUb2tlbkFyZykgeyAkVG9rZW5BcmcgfSBlbHNlaWYgKCRlbnY6TUlNT19BUElfS0VZKSB7ICRlbnY6TUlNT19BUElfS0VZIH0gZWxzZSB7ICIiIH0NCiAgICBicmVhaw0KICB9DQogIHsgJF8gLWluIEAoImRlZXBzZWVrIiwgImRzIikgfSB7DQogICAgJFByb3ZpZGVyID0gImRlZXBzZWVrIg0KICAgICRUb2tlbiA9IGlmICgkVG9rZW5BcmcpIHsgJFRva2VuQXJnIH0gZWxzZWlmICgkZW52OkRFRVBTRUVLX0FQSV9LRVkpIHsgJGVudjpERUVQU0VFS19BUElfS0VZIH0gZWxzZSB7ICIiIH0NCiAgICBicmVhaw0KICB9DQogIHsgJF8gLWluIEAoIi0taGVscCIsICItaCIsICIiKSB9IHsNCiAgICBTaG93LVVzYWdlDQogICAgZXhpdCAwDQogIH0NCiAgZGVmYXVsdCB7DQogICAgdGhyb3cgIlVua25vd24gcHJvdmlkZXI6ICRQcm92aWRlckFyZy4gVXNlOiBtaW1vIG9yIGRlZXBzZWVrIg0KICB9DQp9DQoNCmlmICgtbm90ICRUb2tlbikgew0KICAkc2VjdXJlS2V5ID0gUmVhZC1Ib3N0ICJFbnRlciAkUHJvdmlkZXIgQVBJIGtleSIgLUFzU2VjdXJlU3RyaW5nDQogICRic3RyID0gW1J1bnRpbWUuSW50ZXJvcFNlcnZpY2VzLk1hcnNoYWxdOjpTZWN1cmVTdHJpbmdUb0JTVFIoJHNlY3VyZUtleSkNCiAgdHJ5IHsNCiAgICAkVG9rZW4gPSBbUnVudGltZS5JbnRlcm9wU2VydmljZXMuTWFyc2hhbF06OlB0clRvU3RyaW5nQlNUUigkYnN0cikNCiAgfQ0KICBmaW5hbGx5IHsNCiAgICBbUnVudGltZS5JbnRlcm9wU2VydmljZXMuTWFyc2hhbF06Olplcm9GcmVlQlNUUigkYnN0cikNCiAgfQ0KfQ0KDQppZiAoLW5vdCAkVG9rZW4pIHsNCiAgdGhyb3cgIkFQSSBrZXkgaXMgcmVxdWlyZWQuIg0KfQ0KDQokc2V0dGluZ3NEaXIgPSBTcGxpdC1QYXRoIC1QYXJlbnQgJFByb3ZpZGVyRmlsZQ0KTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtRm9yY2UgLVBhdGggJHNldHRpbmdzRGlyIHwgT3V0LU51bGwNCg0KJGVudjpDTEFVREVfS0VZX1BST1ZJREVSID0gJFByb3ZpZGVyDQokZW52OkNMQVVERV9LRVlfVE9LRU4gPSAkVG9rZW4NCiRlbnY6Q0xBVURFX0tFWV9CQVNFX1VSTCA9IGlmICgkUHJvdmlkZXIgLWVxICJtaW1vIikgeyBHZXQtTWltb0Jhc2VVcmwgJFRva2VuIH0gZWxzZSB7ICIiIH0NCiRlbnY6Q0xBVURFX1BST1ZJREVSX0ZJTEUgPSAkUHJvdmlkZXJGaWxlDQokZW52OkNMQVVERV9TRVRUSU5HU19GSUxFID0gJFNldHRpbmdzRmlsZQ0KDQpAJw0KY29uc3QgZnMgPSByZXF1aXJlKCJmcyIpOw0KDQpjb25zdCBwcm92aWRlciA9IHByb2Nlc3MuZW52LkNMQVVERV9LRVlfUFJPVklERVI7DQpjb25zdCB0b2tlbiA9IHByb2Nlc3MuZW52LkNMQVVERV9LRVlfVE9LRU47DQpjb25zdCBiYXNlVXJsID0gcHJvY2Vzcy5lbnYuQ0xBVURFX0tFWV9CQVNFX1VSTCB8fCAiIjsNCmNvbnN0IHByb3ZpZGVyRmlsZSA9IHByb2Nlc3MuZW52LkNMQVVERV9QUk9WSURFUl9GSUxFOw0KY29uc3Qgc2V0dGluZ3NGaWxlID0gcHJvY2Vzcy5lbnYuQ0xBVURFX1NFVFRJTkdTX0ZJTEU7DQoNCmZ1bmN0aW9uIHJlYWRKc29uKGZpbGUpIHsNCiAgaWYgKCFmcy5leGlzdHNTeW5jKGZpbGUpKSByZXR1cm4ge307DQogIHRyeSB7DQogICAgcmV0dXJuIEpTT04ucGFyc2UoZnMucmVhZEZpbGVTeW5jKGZpbGUsICJ1dGY4IikpOw0KICB9IGNhdGNoIChlcnJvcikgew0KICAgIGNvbnN0IGJhY2t1cCA9IGAke2ZpbGV9LmJhay4ke0RhdGUubm93KCl9YDsNCiAgICBmcy5jb3B5RmlsZVN5bmMoZmlsZSwgYmFja3VwKTsNCiAgICBjb25zb2xlLndhcm4oYEV4aXN0aW5nIEpTT04gd2FzIGludmFsaWQuIEJhY2tlZCB1cCB0byAke2JhY2t1cH1gKTsNCiAgICByZXR1cm4ge307DQogIH0NCn0NCg0KY29uc3QgcHJvdmlkZXJDb25maWcgPSByZWFkSnNvbihwcm92aWRlckZpbGUpOw0KcHJvdmlkZXJDb25maWcucHJvdmlkZXJzID0gcHJvdmlkZXJDb25maWcucHJvdmlkZXJzIHx8IHt9Ow0KcHJvdmlkZXJDb25maWcucHJvdmlkZXJzW3Byb3ZpZGVyXSA9IHsNCiAgLi4uKHByb3ZpZGVyQ29uZmlnLnByb3ZpZGVyc1twcm92aWRlcl0gfHwge30pLA0KICBhdXRoVG9rZW46IHRva2VuLA0KfTsNCmlmIChiYXNlVXJsKSB7DQogIHByb3ZpZGVyQ29uZmlnLnByb3ZpZGVyc1twcm92aWRlcl0uYmFzZVVybCA9IGJhc2VVcmw7DQp9DQoNCmZzLndyaXRlRmlsZVN5bmMocHJvdmlkZXJGaWxlLCBgJHtKU09OLnN0cmluZ2lmeShwcm92aWRlckNvbmZpZywgbnVsbCwgMil9XG5gLCB7IG1vZGU6IDBvNjAwIH0pOw0KDQppZiAocHJvdmlkZXJDb25maWcuYWN0aXZlUHJvdmlkZXIgPT09IHByb3ZpZGVyICYmIGZzLmV4aXN0c1N5bmMoc2V0dGluZ3NGaWxlKSkgew0KICBjb25zdCBzZXR0aW5ncyA9IHJlYWRKc29uKHNldHRpbmdzRmlsZSk7DQogIHNldHRpbmdzLmVudiA9IHsNCiAgICAuLi4oc2V0dGluZ3MuZW52IHx8IHt9KSwNCiAgICBBTlRIUk9QSUNfQVVUSF9UT0tFTjogdG9rZW4sDQogICAgLi4uKGJhc2VVcmwgPyB7IEFOVEhST1BJQ19CQVNFX1VSTDogYmFzZVVybCB9IDoge30pLA0KICB9Ow0KICBmcy53cml0ZUZpbGVTeW5jKHNldHRpbmdzRmlsZSwgYCR7SlNPTi5zdHJpbmdpZnkoc2V0dGluZ3MsIG51bGwsIDIpfVxuYCwgeyBtb2RlOiAwbzYwMCB9KTsNCn0NCidAIHwgbm9kZQ0KDQpXcml0ZS1Ib3N0ICJTYXZlZCBBUEkga2V5IGZvciBwcm92aWRlcjogJFByb3ZpZGVyIg0KV3JpdGUtSG9zdCAiSWYgJFByb3ZpZGVyIGlzIGFjdGl2ZSwgQ2xhdWRlIENvZGUgc2V0dGluZ3Mgd2VyZSB1cGRhdGVkIHRvby4iDQo="
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
    $embeddedScript = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIg0KDQokc2NyaXB0RGlyID0gU3BsaXQtUGF0aCAtUGFyZW50ICRNeUludm9jYXRpb24uTXlDb21tYW5kLlBhdGgNCiRwcm92aWRlckNtZCA9IEpvaW4tUGF0aCAkc2NyaXB0RGlyICJjbGF1ZGUtcHJvdmlkZXIuY21kIg0KJHByb3ZpZGVyUHMxID0gSm9pbi1QYXRoICRzY3JpcHREaXIgInN3aXRjaC1wcm92aWRlci5wczEiDQppZiAoVGVzdC1QYXRoICRwcm92aWRlckNtZCkgew0KICAmICRwcm92aWRlckNtZCBtaW1vIEBhcmdzDQogIGV4aXQgJExBU1RFWElUQ09ERQ0KfQ0KaWYgKFRlc3QtUGF0aCAkcHJvdmlkZXJQczEpIHsNCiAgJiBwb3dlcnNoZWxsIC1Ob1Byb2ZpbGUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgJHByb3ZpZGVyUHMxIG1pbW8gQGFyZ3MNCiAgZXhpdCAkTEFTVEVYSVRDT0RFDQp9DQppZiAoR2V0LUNvbW1hbmQgY2xhdWRlLXByb3ZpZGVyIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSB7DQogICYgY2xhdWRlLXByb3ZpZGVyIG1pbW8gQGFyZ3MNCiAgZXhpdCAkTEFTVEVYSVRDT0RFDQp9DQoNCiRNb2RlbEFyZyA9IGlmICgkYXJncy5Db3VudCAtZ3QgMCkgeyAkYXJnc1swXSB9IGVsc2UgeyAiIiB9DQoNCmZ1bmN0aW9uIEdldC1NaW1vQmFzZVVybCB7DQogIGlmICgkZW52Ok1JTU9fQU5USFJPUElDX0JBU0VfVVJMKSB7DQogICAgcmV0dXJuICRlbnY6TUlNT19BTlRIUk9QSUNfQkFTRV9VUkwNCiAgfQ0KDQogIGlmICgkZW52Ok1JTU9fQVBJX0tFWSAtbGlrZSAidHAtKiIpIHsNCiAgICByZXR1cm4gImh0dHBzOi8vdG9rZW4tcGxhbi1jbi54aWFvbWltaW1vLmNvbS9hbnRocm9waWMiDQogIH0NCg0KICByZXR1cm4gImh0dHBzOi8vYXBpLnhpYW9taW1pbW8uY29tL2FudGhyb3BpYyINCn0NCg0KJEJhc2VVcmwgPSBHZXQtTWltb0Jhc2VVcmwNCg0Kc3dpdGNoICgkTW9kZWxBcmcpIHsNCiAgeyAkXyAtaW4gQCgiZmxhc2giLCAidjItZmxhc2giLCAibWltby12Mi1mbGFzaCIpIH0geyAkTW9kZWwgPSAibWltby12Mi1mbGFzaCI7IGJyZWFrIH0NCiAgeyAkXyAtaW4gQCgicHJvIiwgInYyLjUtcHJvIiwgIm1pbW8tdjIuNS1wcm8iLCAidjItcHJvIiwgIm1pbW8tdjItcHJvIikgfSB7ICRNb2RlbCA9ICJtaW1vLXYyLjUtcHJvIjsgYnJlYWsgfQ0KICB7ICRfIC1pbiBAKCJvbW5pIiwgInYyLjUiLCAibWltby12Mi41IiwgInYyLW9tbmkiLCAibWltby12Mi1vbW5pIikgfSB7ICRNb2RlbCA9ICJtaW1vLXYyLjUiOyBicmVhayB9DQogIHsgJF8gLWluIEAoIi0taGVscCIsICItaCIsICIiKSB9IHsNCiAgICBXcml0ZS1Ib3N0ICJVc2FnZTogLlxzd2l0Y2gtbWltby5wczEgPGZsYXNofHByb3xvbW5pfG1vZGVsLW5hbWU+Ig0KICAgIFdyaXRlLUhvc3QgIiINCiAgICBXcml0ZS1Ib3N0ICJTd2l0Y2ggQ2xhdWRlIENvZGUgdG8gYSBYaWFvbWkgTWlNbyBtb2RlbC4iDQogICAgZXhpdCAwDQogIH0NCiAgZGVmYXVsdCB7DQogICAgJE1vZGVsID0gJE1vZGVsQXJnDQogIH0NCn0NCg0KJHNldHRpbmdzRGlyID0gSm9pbi1QYXRoICRIT01FICIuY2xhdWRlIg0KJHNldHRpbmdzRmlsZSA9IEpvaW4tUGF0aCAkc2V0dGluZ3NEaXIgInNldHRpbmdzLmpzb24iDQpOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1Gb3JjZSAtUGF0aCAkc2V0dGluZ3NEaXIgfCBPdXQtTnVsbA0KDQokZW52OkNMQVVERV9TRVRUSU5HU19GSUxFID0gJHNldHRpbmdzRmlsZQ0KJGVudjpNSU1PX01PREVMX0VGRkVDVElWRSA9ICRNb2RlbA0KJGVudjpNSU1PX0JBU0VfVVJMX0VGRkVDVElWRSA9ICRCYXNlVXJsDQoNCkAnDQpjb25zdCBmcyA9IHJlcXVpcmUoImZzIik7DQoNCmNvbnN0IHNldHRpbmdzRmlsZSA9IHByb2Nlc3MuZW52LkNMQVVERV9TRVRUSU5HU19GSUxFOw0KY29uc3QgbW9kZWwgPSBwcm9jZXNzLmVudi5NSU1PX01PREVMX0VGRkVDVElWRTsNCmNvbnN0IGJhc2VVcmwgPSBwcm9jZXNzLmVudi5NSU1PX0JBU0VfVVJMX0VGRkVDVElWRTsNCg0KbGV0IHNldHRpbmdzID0ge307DQppZiAoZnMuZXhpc3RzU3luYyhzZXR0aW5nc0ZpbGUpKSB7DQogIHRyeSB7DQogICAgc2V0dGluZ3MgPSBKU09OLnBhcnNlKGZzLnJlYWRGaWxlU3luYyhzZXR0aW5nc0ZpbGUsICJ1dGY4IikpOw0KICB9IGNhdGNoIChlcnJvcikgew0KICAgIGNvbnN0IGJhY2t1cCA9IGAke3NldHRpbmdzRmlsZX0uYmFrLiR7RGF0ZS5ub3coKX1gOw0KICAgIGZzLmNvcHlGaWxlU3luYyhzZXR0aW5nc0ZpbGUsIGJhY2t1cCk7DQogICAgY29uc29sZS53YXJuKGBFeGlzdGluZyBzZXR0aW5ncyB3ZXJlIGludmFsaWQgSlNPTi4gQmFja2VkIHVwIHRvICR7YmFja3VwfWApOw0KICB9DQp9DQoNCnNldHRpbmdzLmVudiA9IHsNCiAgLi4uKHNldHRpbmdzLmVudiB8fCB7fSksDQogIEFOVEhST1BJQ19CQVNFX1VSTDogYmFzZVVybCwNCiAgQU5USFJPUElDX01PREVMOiBtb2RlbCwNCiAgQU5USFJPUElDX0RFRkFVTFRfSEFJS1VfTU9ERUw6IG1vZGVsLA0KICBBTlRIUk9QSUNfREVGQVVMVF9TT05ORVRfTU9ERUw6IG1vZGVsLA0KICBBTlRIUk9QSUNfREVGQVVMVF9PUFVTX01PREVMOiBtb2RlbCwNCn07DQoNCmlmIChzZXR0aW5ncy5pbmNsdWRlQ29BdXRob3JlZEJ5ID09PSB1bmRlZmluZWQpIHsNCiAgc2V0dGluZ3MuaW5jbHVkZUNvQXV0aG9yZWRCeSA9IGZhbHNlOw0KfQ0KDQpmcy53cml0ZUZpbGVTeW5jKHNldHRpbmdzRmlsZSwgYCR7SlNPTi5zdHJpbmdpZnkoc2V0dGluZ3MsIG51bGwsIDIpfVxuYCwgeyBtb2RlOiAwbzYwMCB9KTsNCidAIHwgbm9kZQ0KDQpXcml0ZS1Ib3N0ICJDbGF1ZGUgQ29kZSBNaU1vIG1vZGVsIHNldCB0bzogJE1vZGVsIg0KV3JpdGUtSG9zdCAiUnVuOiBjbGF1ZGUiDQo="
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

if (-not $SkipMimoConfig -and -not $env:MIMO_API_KEY) {
  $secureKey = Read-Host "Enter your MiMo API key" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
  try {
    $env:MIMO_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

if (-not $SkipMimoConfig -and -not $env:MIMO_API_KEY) {
  throw "MiMo API key is required."
}

$BaseUrl = Get-MimoBaseUrl $env:MIMO_API_KEY

Install-ClaudeCodeNative

if (-not $SkipMimoConfig) {
  $settingsDir = Join-Path $HOME ".claude"
  $settingsFile = Join-Path $settingsDir "settings.json"
  $claudeJsonFile = Join-Path $HOME ".claude.json"
  $providerFile = Join-Path $settingsDir "provider-switch.json"

  $settings = Read-JsonFile $settingsFile
  if (-not (Test-MapKey $settings "env") -or -not (Get-MapValue $settings "env")) {
    Set-MapValue $settings "env" ([ordered]@{})
  }

  $settingsEnv = Get-MapValue $settings "env"
  Set-MapValue $settingsEnv "ANTHROPIC_BASE_URL" $BaseUrl
  Set-MapValue $settingsEnv "ANTHROPIC_AUTH_TOKEN" $env:MIMO_API_KEY
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
  Set-MapValue $providers "mimo" ([ordered]@{
    baseUrl = $BaseUrl
    authToken = $env:MIMO_API_KEY
  })

  if ($env:DEEPSEEK_API_KEY) {
    Set-MapValue $providers "deepseek" ([ordered]@{
      baseUrl = $DeepSeekBaseUrl
      authToken = $env:DEEPSEEK_API_KEY
    })
  }

  Set-MapValue $providerConfig "activeProvider" "mimo"
  Set-MapValue $providerConfig "activeModel" $Model
  Write-JsonFile $providerFile $providerConfig

  $claudeJson = Read-JsonFile $claudeJsonFile
  Set-MapValue $claudeJson "hasCompletedOnboarding" $true
  Write-JsonFile $claudeJsonFile $claudeJson

  Write-Host "Done. Claude Code is configured for MiMo model: $Model"
}
else {
  Write-Host "Skipped MiMo API configuration."
}

Install-MimoSwitcher
Install-ProviderSwitcher
Install-ProviderKeySetter
Install-ClaudeCommandShim

Write-Host ""
Write-Host "Restart CMD/PowerShell if new commands are not recognized."
Write-Host "Run: claude"
Write-Host "Switch provider/model with: claude-provider mimo flash"
Write-Host "Switch provider/model with: claude-provider mimo pro"
Write-Host "Switch provider/model with: claude-provider mimo omni"
Write-Host "Switch provider/model with: claude-provider deepseek pro"
