$ErrorActionPreference = "Stop"

$Model = if ($env:MIMO_MODEL) { $env:MIMO_MODEL } else { "mimo-v2-flash" }
$BaseUrl = if ($env:MIMO_ANTHROPIC_BASE_URL) { $env:MIMO_ANTHROPIC_BASE_URL } else { "https://api.xiaomimimo.com/anthropic" }
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
      Write-Host "  MIMO_MODEL                   Model name, default: mimo-v2-flash"
      Write-Host "  MIMO_ANTHROPIC_BASE_URL      API base URL"
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

function Install-ClaudeCodeNative {
  if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-Host "Removing old npm Claude Code package if present..."
    try {
      npm uninstall -g "@anthropic-ai/claude-code" | Out-Host
    }
    catch {
      Write-Warning "npm uninstall failed or package was not present. Continuing with native installer."
    }
  }

  Write-Host "Installing or updating Claude Code with the official Windows installer..."
  Invoke-Expression (Invoke-RestMethod "https://claude.ai/install.ps1")
  Ensure-ClaudePath
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
    $embeddedScript = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIgoKJFByb3ZpZGVyQXJnID0gaWYgKCRhcmdzLkNvdW50IC1ndCAwKSB7ICRhcmdzWzBdIH0gZWxzZSB7ICIiIH0KJE1vZGVsQXJnID0gaWYgKCRhcmdzLkNvdW50IC1ndCAxKSB7ICRhcmdzWzFdIH0gZWxzZSB7ICIiIH0KJFNldHRpbmdzRmlsZSA9IEpvaW4tUGF0aCAkSE9NRSAiLmNsYXVkZVxzZXR0aW5ncy5qc29uIgokUHJvdmlkZXJGaWxlID0gSm9pbi1QYXRoICRIT01FICIuY2xhdWRlXHByb3ZpZGVyLXN3aXRjaC5qc29uIgoKZnVuY3Rpb24gU2hvdy1Vc2FnZSB7CiAgV3JpdGUtSG9zdCAiVXNhZ2U6IgogIFdyaXRlLUhvc3QgIiAgY2xhdWRlLXByb3ZpZGVyIG1pbW8gPGZsYXNofHByb3xvbW5pfG1vZGVsLW5hbWU+IgogIFdyaXRlLUhvc3QgIiAgY2xhdWRlLXByb3ZpZGVyIGRlZXBzZWVrIDxmbGFzaHxwcm98bW9kZWwtbmFtZT4iCiAgV3JpdGUtSG9zdCAiIgogIFdyaXRlLUhvc3QgIkVudmlyb25tZW50OiIKICBXcml0ZS1Ib3N0ICIgIE1JTU9fQVBJX0tFWSAgICAgICAgICAgICAgICAgWGlhb21pIE1pTW8gQVBJIGtleSIKICBXcml0ZS1Ib3N0ICIgIERFRVBTRUVLX0FQSV9LRVkgICAgICAgICAgICAgRGVlcFNlZWsgQVBJIGtleSIKICBXcml0ZS1Ib3N0ICIgIE1JTU9fQU5USFJPUElDX0JBU0VfVVJMICAgICAgRGVmYXVsdDogaHR0cHM6Ly9hcGkueGlhb21pbWltby5jb20vYW50aHJvcGljIgogIFdyaXRlLUhvc3QgIiAgREVFUFNFRUtfQU5USFJPUElDX0JBU0VfVVJMICBEZWZhdWx0OiBodHRwczovL2FwaS5kZWVwc2Vlay5jb20vYW50aHJvcGljIgp9Cgpzd2l0Y2ggKCRQcm92aWRlckFyZykgewogIHsgJF8gLWluIEAoIm1pbW8iLCAieGlhb21pLW1pbW8iKSB9IHsKICAgICRQcm92aWRlciA9ICJtaW1vIgogICAgJEJhc2VVcmwgPSBpZiAoJGVudjpNSU1PX0FOVEhST1BJQ19CQVNFX1VSTCkgeyAkZW52Ok1JTU9fQU5USFJPUElDX0JBU0VfVVJMIH0gZWxzZSB7ICJodHRwczovL2FwaS54aWFvbWltaW1vLmNvbS9hbnRocm9waWMiIH0KICAgICRUb2tlbiA9IGlmICgkZW52Ok1JTU9fQVBJX0tFWSkgeyAkZW52Ok1JTU9fQVBJX0tFWSB9IGVsc2UgeyAiIiB9CiAgICBzd2l0Y2ggKCRNb2RlbEFyZykgewogICAgICB7ICRfIC1pbiBAKCJmbGFzaCIsICJ2Mi1mbGFzaCIsICJtaW1vLXYyLWZsYXNoIiwgIiIpIH0geyAkTW9kZWwgPSAibWltby12Mi1mbGFzaCI7IGJyZWFrIH0KICAgICAgeyAkXyAtaW4gQCgicHJvIiwgInYyLXBybyIsICJtaW1vLXYyLXBybyIpIH0geyAkTW9kZWwgPSAibWltby12Mi1wcm8iOyBicmVhayB9CiAgICAgIHsgJF8gLWluIEAoIm9tbmkiLCAidjItb21uaSIsICJtaW1vLXYyLW9tbmkiKSB9IHsgJE1vZGVsID0gIm1pbW8tdjItb21uaSI7IGJyZWFrIH0KICAgICAgeyAkXyAtaW4gQCgiLS1oZWxwIiwgIi1oIikgfSB7IFNob3ctVXNhZ2U7IGV4aXQgMCB9CiAgICAgIGRlZmF1bHQgeyAkTW9kZWwgPSAkTW9kZWxBcmcgfQogICAgfQogICAgYnJlYWsKICB9CiAgeyAkXyAtaW4gQCgiZGVlcHNlZWsiLCAiZHMiKSB9IHsKICAgICRQcm92aWRlciA9ICJkZWVwc2VlayIKICAgICRCYXNlVXJsID0gaWYgKCRlbnY6REVFUFNFRUtfQU5USFJPUElDX0JBU0VfVVJMKSB7ICRlbnY6REVFUFNFRUtfQU5USFJPUElDX0JBU0VfVVJMIH0gZWxzZSB7ICJodHRwczovL2FwaS5kZWVwc2Vlay5jb20vYW50aHJvcGljIiB9CiAgICAkVG9rZW4gPSBpZiAoJGVudjpERUVQU0VFS19BUElfS0VZKSB7ICRlbnY6REVFUFNFRUtfQVBJX0tFWSB9IGVsc2UgeyAiIiB9CiAgICBzd2l0Y2ggKCRNb2RlbEFyZykgewogICAgICB7ICRfIC1pbiBAKCJmbGFzaCIsICJ2NC1mbGFzaCIsICJkZWVwc2Vlay12NC1mbGFzaCIsICIiKSB9IHsgJE1vZGVsID0gImRlZXBzZWVrLXY0LWZsYXNoIjsgYnJlYWsgfQogICAgICB7ICRfIC1pbiBAKCJwcm8iLCAidjQtcHJvIiwgImRlZXBzZWVrLXY0LXBybyIpIH0geyAkTW9kZWwgPSAiZGVlcHNlZWstdjQtcHJvIjsgYnJlYWsgfQogICAgICB7ICRfIC1pbiBAKCItLWhlbHAiLCAiLWgiKSB9IHsgU2hvdy1Vc2FnZTsgZXhpdCAwIH0KICAgICAgZGVmYXVsdCB7ICRNb2RlbCA9ICRNb2RlbEFyZyB9CiAgICB9CiAgICBicmVhawogIH0KICB7ICRfIC1pbiBAKCItLWhlbHAiLCAiLWgiLCAiIikgfSB7CiAgICBTaG93LVVzYWdlCiAgICBleGl0IDAKICB9CiAgZGVmYXVsdCB7CiAgICB0aHJvdyAiVW5rbm93biBwcm92aWRlcjogJFByb3ZpZGVyQXJnLiBVc2U6IG1pbW8gb3IgZGVlcHNlZWsiCiAgfQp9Cgokc2V0dGluZ3NEaXIgPSBTcGxpdC1QYXRoIC1QYXJlbnQgJFNldHRpbmdzRmlsZQpOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1Gb3JjZSAtUGF0aCAkc2V0dGluZ3NEaXIgfCBPdXQtTnVsbAoKJGVudjpDTEFVREVfU0VUVElOR1NfRklMRSA9ICRTZXR0aW5nc0ZpbGUKJGVudjpDTEFVREVfUFJPVklERVJfRklMRSA9ICRQcm92aWRlckZpbGUKJGVudjpDTEFVREVfUFJPVklERVJfRUZGRUNUSVZFID0gJFByb3ZpZGVyCiRlbnY6Q0xBVURFX01PREVMX0VGRkVDVElWRSA9ICRNb2RlbAokZW52OkNMQVVERV9CQVNFX1VSTF9FRkZFQ1RJVkUgPSAkQmFzZVVybAokZW52OkNMQVVERV9UT0tFTl9FRkZFQ1RJVkUgPSAkVG9rZW4KCkAnCmNvbnN0IGZzID0gcmVxdWlyZSgiZnMiKTsKCmNvbnN0IHNldHRpbmdzRmlsZSA9IHByb2Nlc3MuZW52LkNMQVVERV9TRVRUSU5HU19GSUxFOwpjb25zdCBwcm92aWRlckZpbGUgPSBwcm9jZXNzLmVudi5DTEFVREVfUFJPVklERVJfRklMRTsKY29uc3QgcHJvdmlkZXIgPSBwcm9jZXNzLmVudi5DTEFVREVfUFJPVklERVJfRUZGRUNUSVZFOwpjb25zdCBtb2RlbCA9IHByb2Nlc3MuZW52LkNMQVVERV9NT0RFTF9FRkZFQ1RJVkU7CmNvbnN0IGJhc2VVcmwgPSBwcm9jZXNzLmVudi5DTEFVREVfQkFTRV9VUkxfRUZGRUNUSVZFOwpjb25zdCB0b2tlbkZyb21FbnYgPSBwcm9jZXNzLmVudi5DTEFVREVfVE9LRU5fRUZGRUNUSVZFIHx8ICIiOwoKZnVuY3Rpb24gcmVhZEpzb24oZmlsZSkgewogIGlmICghZnMuZXhpc3RzU3luYyhmaWxlKSkgcmV0dXJuIHt9OwogIHRyeSB7CiAgICByZXR1cm4gSlNPTi5wYXJzZShmcy5yZWFkRmlsZVN5bmMoZmlsZSwgInV0ZjgiKSk7CiAgfSBjYXRjaCAoZXJyb3IpIHsKICAgIGNvbnN0IGJhY2t1cCA9IGAke2ZpbGV9LmJhay4ke0RhdGUubm93KCl9YDsKICAgIGZzLmNvcHlGaWxlU3luYyhmaWxlLCBiYWNrdXApOwogICAgY29uc29sZS53YXJuKGBFeGlzdGluZyBKU09OIHdhcyBpbnZhbGlkLiBCYWNrZWQgdXAgdG8gJHtiYWNrdXB9YCk7CiAgICByZXR1cm4ge307CiAgfQp9Cgpjb25zdCBwcm92aWRlckNvbmZpZyA9IHJlYWRKc29uKHByb3ZpZGVyRmlsZSk7CnByb3ZpZGVyQ29uZmlnLnByb3ZpZGVycyA9IHByb3ZpZGVyQ29uZmlnLnByb3ZpZGVycyB8fCB7fTsKcHJvdmlkZXJDb25maWcucHJvdmlkZXJzW3Byb3ZpZGVyXSA9IHsKICAuLi4ocHJvdmlkZXJDb25maWcucHJvdmlkZXJzW3Byb3ZpZGVyXSB8fCB7fSksCiAgYmFzZVVybCwKfTsKCmlmICh0b2tlbkZyb21FbnYpIHsKICBwcm92aWRlckNvbmZpZy5wcm92aWRlcnNbcHJvdmlkZXJdLmF1dGhUb2tlbiA9IHRva2VuRnJvbUVudjsKfQoKY29uc3QgdG9rZW4gPSBwcm92aWRlckNvbmZpZy5wcm92aWRlcnNbcHJvdmlkZXJdLmF1dGhUb2tlbjsKaWYgKCF0b2tlbikgewogIGNvbnN0IGVudk5hbWUgPSBwcm92aWRlciA9PT0gIm1pbW8iID8gIk1JTU9fQVBJX0tFWSIgOiAiREVFUFNFRUtfQVBJX0tFWSI7CiAgY29uc29sZS5lcnJvcihgTWlzc2luZyBBUEkga2V5IGZvciAke3Byb3ZpZGVyfS4gUmUtcnVuIHdpdGggJHtlbnZOYW1lfT0uLi4gb25jZS5gKTsKICBwcm9jZXNzLmV4aXQoMSk7Cn0KCnByb3ZpZGVyQ29uZmlnLmFjdGl2ZVByb3ZpZGVyID0gcHJvdmlkZXI7CnByb3ZpZGVyQ29uZmlnLmFjdGl2ZU1vZGVsID0gbW9kZWw7CmZzLndyaXRlRmlsZVN5bmMocHJvdmlkZXJGaWxlLCBgJHtKU09OLnN0cmluZ2lmeShwcm92aWRlckNvbmZpZywgbnVsbCwgMil9XG5gLCB7IG1vZGU6IDBvNjAwIH0pOwoKY29uc3Qgc2V0dGluZ3MgPSByZWFkSnNvbihzZXR0aW5nc0ZpbGUpOwpzZXR0aW5ncy5lbnYgPSB7CiAgLi4uKHNldHRpbmdzLmVudiB8fCB7fSksCiAgQU5USFJPUElDX0JBU0VfVVJMOiBiYXNlVXJsLAogIEFOVEhST1BJQ19BVVRIX1RPS0VOOiB0b2tlbiwKICBBTlRIUk9QSUNfTU9ERUw6IG1vZGVsLAogIEFOVEhST1BJQ19ERUZBVUxUX0hBSUtVX01PREVMOiBtb2RlbCwKICBBTlRIUk9QSUNfREVGQVVMVF9TT05ORVRfTU9ERUw6IG1vZGVsLAogIEFOVEhST1BJQ19ERUZBVUxUX09QVVNfTU9ERUw6IG1vZGVsLAp9OwoKaWYgKHNldHRpbmdzLmluY2x1ZGVDb0F1dGhvcmVkQnkgPT09IHVuZGVmaW5lZCkgewogIHNldHRpbmdzLmluY2x1ZGVDb0F1dGhvcmVkQnkgPSBmYWxzZTsKfQoKZnMud3JpdGVGaWxlU3luYyhzZXR0aW5nc0ZpbGUsIGAke0pTT04uc3RyaW5naWZ5KHNldHRpbmdzLCBudWxsLCAyKX1cbmAsIHsgbW9kZTogMG82MDAgfSk7CidAIHwgbm9kZQoKV3JpdGUtSG9zdCAiQ2xhdWRlIENvZGUgcHJvdmlkZXIgc2V0IHRvOiAkUHJvdmlkZXIiCldyaXRlLUhvc3QgIkNsYXVkZSBDb2RlIG1vZGVsIHNldCB0bzogJE1vZGVsIgpXcml0ZS1Ib3N0ICJSdW46IGNsYXVkZSIK"
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
    $embeddedScript = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIgoKJFByb3ZpZGVyQXJnID0gaWYgKCRhcmdzLkNvdW50IC1ndCAwKSB7ICRhcmdzWzBdIH0gZWxzZSB7ICIiIH0KJFRva2VuQXJnID0gaWYgKCRhcmdzLkNvdW50IC1ndCAxKSB7ICRhcmdzWzFdIH0gZWxzZSB7ICIiIH0KJFByb3ZpZGVyRmlsZSA9IEpvaW4tUGF0aCAkSE9NRSAiLmNsYXVkZVxwcm92aWRlci1zd2l0Y2guanNvbiIKJFNldHRpbmdzRmlsZSA9IEpvaW4tUGF0aCAkSE9NRSAiLmNsYXVkZVxzZXR0aW5ncy5qc29uIgoKZnVuY3Rpb24gU2hvdy1Vc2FnZSB7CiAgV3JpdGUtSG9zdCAiVXNhZ2U6IgogIFdyaXRlLUhvc3QgIiAgY2xhdWRlLXByb3ZpZGVyLWtleSBtaW1vIFthcGkta2V5XSIKICBXcml0ZS1Ib3N0ICIgIGNsYXVkZS1wcm92aWRlci1rZXkgZGVlcHNlZWsgW2FwaS1rZXldIgogIFdyaXRlLUhvc3QgIiIKICBXcml0ZS1Ib3N0ICJFbnZpcm9ubWVudDoiCiAgV3JpdGUtSG9zdCAiICBNSU1PX0FQSV9LRVkgICAgICBYaWFvbWkgTWlNbyBBUEkga2V5IgogIFdyaXRlLUhvc3QgIiAgREVFUFNFRUtfQVBJX0tFWSAgRGVlcFNlZWsgQVBJIGtleSIKfQoKc3dpdGNoICgkUHJvdmlkZXJBcmcpIHsKICB7ICRfIC1pbiBAKCJtaW1vIiwgInhpYW9taS1taW1vIikgfSB7CiAgICAkUHJvdmlkZXIgPSAibWltbyIKICAgICRUb2tlbiA9IGlmICgkVG9rZW5BcmcpIHsgJFRva2VuQXJnIH0gZWxzZWlmICgkZW52Ok1JTU9fQVBJX0tFWSkgeyAkZW52Ok1JTU9fQVBJX0tFWSB9IGVsc2UgeyAiIiB9CiAgICBicmVhawogIH0KICB7ICRfIC1pbiBAKCJkZWVwc2VlayIsICJkcyIpIH0gewogICAgJFByb3ZpZGVyID0gImRlZXBzZWVrIgogICAgJFRva2VuID0gaWYgKCRUb2tlbkFyZykgeyAkVG9rZW5BcmcgfSBlbHNlaWYgKCRlbnY6REVFUFNFRUtfQVBJX0tFWSkgeyAkZW52OkRFRVBTRUVLX0FQSV9LRVkgfSBlbHNlIHsgIiIgfQogICAgYnJlYWsKICB9CiAgeyAkXyAtaW4gQCgiLS1oZWxwIiwgIi1oIiwgIiIpIH0gewogICAgU2hvdy1Vc2FnZQogICAgZXhpdCAwCiAgfQogIGRlZmF1bHQgewogICAgdGhyb3cgIlVua25vd24gcHJvdmlkZXI6ICRQcm92aWRlckFyZy4gVXNlOiBtaW1vIG9yIGRlZXBzZWVrIgogIH0KfQoKaWYgKC1ub3QgJFRva2VuKSB7CiAgJHNlY3VyZUtleSA9IFJlYWQtSG9zdCAiRW50ZXIgJFByb3ZpZGVyIEFQSSBrZXkiIC1Bc1NlY3VyZVN0cmluZwogICRic3RyID0gW1J1bnRpbWUuSW50ZXJvcFNlcnZpY2VzLk1hcnNoYWxdOjpTZWN1cmVTdHJpbmdUb0JTVFIoJHNlY3VyZUtleSkKICB0cnkgewogICAgJFRva2VuID0gW1J1bnRpbWUuSW50ZXJvcFNlcnZpY2VzLk1hcnNoYWxdOjpQdHJUb1N0cmluZ0JTVFIoJGJzdHIpCiAgfQogIGZpbmFsbHkgewogICAgW1J1bnRpbWUuSW50ZXJvcFNlcnZpY2VzLk1hcnNoYWxdOjpaZXJvRnJlZUJTVFIoJGJzdHIpCiAgfQp9CgppZiAoLW5vdCAkVG9rZW4pIHsKICB0aHJvdyAiQVBJIGtleSBpcyByZXF1aXJlZC4iCn0KCiRzZXR0aW5nc0RpciA9IFNwbGl0LVBhdGggLVBhcmVudCAkUHJvdmlkZXJGaWxlCk5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLUZvcmNlIC1QYXRoICRzZXR0aW5nc0RpciB8IE91dC1OdWxsCgokZW52OkNMQVVERV9LRVlfUFJPVklERVIgPSAkUHJvdmlkZXIKJGVudjpDTEFVREVfS0VZX1RPS0VOID0gJFRva2VuCiRlbnY6Q0xBVURFX1BST1ZJREVSX0ZJTEUgPSAkUHJvdmlkZXJGaWxlCiRlbnY6Q0xBVURFX1NFVFRJTkdTX0ZJTEUgPSAkU2V0dGluZ3NGaWxlCgpAJwpjb25zdCBmcyA9IHJlcXVpcmUoImZzIik7Cgpjb25zdCBwcm92aWRlciA9IHByb2Nlc3MuZW52LkNMQVVERV9LRVlfUFJPVklERVI7CmNvbnN0IHRva2VuID0gcHJvY2Vzcy5lbnYuQ0xBVURFX0tFWV9UT0tFTjsKY29uc3QgcHJvdmlkZXJGaWxlID0gcHJvY2Vzcy5lbnYuQ0xBVURFX1BST1ZJREVSX0ZJTEU7CmNvbnN0IHNldHRpbmdzRmlsZSA9IHByb2Nlc3MuZW52LkNMQVVERV9TRVRUSU5HU19GSUxFOwoKZnVuY3Rpb24gcmVhZEpzb24oZmlsZSkgewogIGlmICghZnMuZXhpc3RzU3luYyhmaWxlKSkgcmV0dXJuIHt9OwogIHRyeSB7CiAgICByZXR1cm4gSlNPTi5wYXJzZShmcy5yZWFkRmlsZVN5bmMoZmlsZSwgInV0ZjgiKSk7CiAgfSBjYXRjaCAoZXJyb3IpIHsKICAgIGNvbnN0IGJhY2t1cCA9IGAke2ZpbGV9LmJhay4ke0RhdGUubm93KCl9YDsKICAgIGZzLmNvcHlGaWxlU3luYyhmaWxlLCBiYWNrdXApOwogICAgY29uc29sZS53YXJuKGBFeGlzdGluZyBKU09OIHdhcyBpbnZhbGlkLiBCYWNrZWQgdXAgdG8gJHtiYWNrdXB9YCk7CiAgICByZXR1cm4ge307CiAgfQp9Cgpjb25zdCBwcm92aWRlckNvbmZpZyA9IHJlYWRKc29uKHByb3ZpZGVyRmlsZSk7CnByb3ZpZGVyQ29uZmlnLnByb3ZpZGVycyA9IHByb3ZpZGVyQ29uZmlnLnByb3ZpZGVycyB8fCB7fTsKcHJvdmlkZXJDb25maWcucHJvdmlkZXJzW3Byb3ZpZGVyXSA9IHsKICAuLi4ocHJvdmlkZXJDb25maWcucHJvdmlkZXJzW3Byb3ZpZGVyXSB8fCB7fSksCiAgYXV0aFRva2VuOiB0b2tlbiwKfTsKCmZzLndyaXRlRmlsZVN5bmMocHJvdmlkZXJGaWxlLCBgJHtKU09OLnN0cmluZ2lmeShwcm92aWRlckNvbmZpZywgbnVsbCwgMil9XG5gLCB7IG1vZGU6IDBvNjAwIH0pOwoKaWYgKHByb3ZpZGVyQ29uZmlnLmFjdGl2ZVByb3ZpZGVyID09PSBwcm92aWRlciAmJiBmcy5leGlzdHNTeW5jKHNldHRpbmdzRmlsZSkpIHsKICBjb25zdCBzZXR0aW5ncyA9IHJlYWRKc29uKHNldHRpbmdzRmlsZSk7CiAgc2V0dGluZ3MuZW52ID0gewogICAgLi4uKHNldHRpbmdzLmVudiB8fCB7fSksCiAgICBBTlRIUk9QSUNfQVVUSF9UT0tFTjogdG9rZW4sCiAgfTsKICBmcy53cml0ZUZpbGVTeW5jKHNldHRpbmdzRmlsZSwgYCR7SlNPTi5zdHJpbmdpZnkoc2V0dGluZ3MsIG51bGwsIDIpfVxuYCwgeyBtb2RlOiAwbzYwMCB9KTsKfQonQCB8IG5vZGUKCldyaXRlLUhvc3QgIlNhdmVkIEFQSSBrZXkgZm9yIHByb3ZpZGVyOiAkUHJvdmlkZXIiCldyaXRlLUhvc3QgIklmICRQcm92aWRlciBpcyBhY3RpdmUsIENsYXVkZSBDb2RlIHNldHRpbmdzIHdlcmUgdXBkYXRlZCB0b28uIgo="
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
    $embeddedScript = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIgoKJHNjcmlwdERpciA9IFNwbGl0LVBhdGggLVBhcmVudCAkTXlJbnZvY2F0aW9uLk15Q29tbWFuZC5QYXRoCiRwcm92aWRlckNtZCA9IEpvaW4tUGF0aCAkc2NyaXB0RGlyICJjbGF1ZGUtcHJvdmlkZXIuY21kIgokcHJvdmlkZXJQczEgPSBKb2luLVBhdGggJHNjcmlwdERpciAic3dpdGNoLXByb3ZpZGVyLnBzMSIKaWYgKFRlc3QtUGF0aCAkcHJvdmlkZXJDbWQpIHsKICAmICRwcm92aWRlckNtZCBtaW1vIEBhcmdzCiAgZXhpdCAkTEFTVEVYSVRDT0RFCn0KaWYgKFRlc3QtUGF0aCAkcHJvdmlkZXJQczEpIHsKICAmIHBvd2Vyc2hlbGwgLU5vUHJvZmlsZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAkcHJvdmlkZXJQczEgbWltbyBAYXJncwogIGV4aXQgJExBU1RFWElUQ09ERQp9CmlmIChHZXQtQ29tbWFuZCBjbGF1ZGUtcHJvdmlkZXIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpIHsKICAmIGNsYXVkZS1wcm92aWRlciBtaW1vIEBhcmdzCiAgZXhpdCAkTEFTVEVYSVRDT0RFCn0KCiRNb2RlbEFyZyA9IGlmICgkYXJncy5Db3VudCAtZ3QgMCkgeyAkYXJnc1swXSB9IGVsc2UgeyAiIiB9CiRCYXNlVXJsID0gaWYgKCRlbnY6TUlNT19BTlRIUk9QSUNfQkFTRV9VUkwpIHsgJGVudjpNSU1PX0FOVEhST1BJQ19CQVNFX1VSTCB9IGVsc2UgeyAiaHR0cHM6Ly9hcGkueGlhb21pbWltby5jb20vYW50aHJvcGljIiB9Cgpzd2l0Y2ggKCRNb2RlbEFyZykgewogIHsgJF8gLWluIEAoImZsYXNoIiwgInYyLWZsYXNoIiwgIm1pbW8tdjItZmxhc2giKSB9IHsgJE1vZGVsID0gIm1pbW8tdjItZmxhc2giOyBicmVhayB9CiAgeyAkXyAtaW4gQCgicHJvIiwgInYyLXBybyIsICJtaW1vLXYyLXBybyIpIH0geyAkTW9kZWwgPSAibWltby12Mi1wcm8iOyBicmVhayB9CiAgeyAkXyAtaW4gQCgib21uaSIsICJ2Mi1vbW5pIiwgIm1pbW8tdjItb21uaSIpIH0geyAkTW9kZWwgPSAibWltby12Mi1vbW5pIjsgYnJlYWsgfQogIHsgJF8gLWluIEAoIi0taGVscCIsICItaCIsICIiKSB9IHsKICAgIFdyaXRlLUhvc3QgIlVzYWdlOiAuXHN3aXRjaC1taW1vLnBzMSA8Zmxhc2h8cHJvfG9tbml8bW9kZWwtbmFtZT4iCiAgICBXcml0ZS1Ib3N0ICIiCiAgICBXcml0ZS1Ib3N0ICJTd2l0Y2ggQ2xhdWRlIENvZGUgdG8gYSBYaWFvbWkgTWlNbyBtb2RlbC4iCiAgICBleGl0IDAKICB9CiAgZGVmYXVsdCB7CiAgICAkTW9kZWwgPSAkTW9kZWxBcmcKICB9Cn0KCiRzZXR0aW5nc0RpciA9IEpvaW4tUGF0aCAkSE9NRSAiLmNsYXVkZSIKJHNldHRpbmdzRmlsZSA9IEpvaW4tUGF0aCAkc2V0dGluZ3NEaXIgInNldHRpbmdzLmpzb24iCk5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLUZvcmNlIC1QYXRoICRzZXR0aW5nc0RpciB8IE91dC1OdWxsCgokZW52OkNMQVVERV9TRVRUSU5HU19GSUxFID0gJHNldHRpbmdzRmlsZQokZW52Ok1JTU9fTU9ERUxfRUZGRUNUSVZFID0gJE1vZGVsCiRlbnY6TUlNT19CQVNFX1VSTF9FRkZFQ1RJVkUgPSAkQmFzZVVybAoKQCcKY29uc3QgZnMgPSByZXF1aXJlKCJmcyIpOwoKY29uc3Qgc2V0dGluZ3NGaWxlID0gcHJvY2Vzcy5lbnYuQ0xBVURFX1NFVFRJTkdTX0ZJTEU7CmNvbnN0IG1vZGVsID0gcHJvY2Vzcy5lbnYuTUlNT19NT0RFTF9FRkZFQ1RJVkU7CmNvbnN0IGJhc2VVcmwgPSBwcm9jZXNzLmVudi5NSU1PX0JBU0VfVVJMX0VGRkVDVElWRTsKCmxldCBzZXR0aW5ncyA9IHt9OwppZiAoZnMuZXhpc3RzU3luYyhzZXR0aW5nc0ZpbGUpKSB7CiAgdHJ5IHsKICAgIHNldHRpbmdzID0gSlNPTi5wYXJzZShmcy5yZWFkRmlsZVN5bmMoc2V0dGluZ3NGaWxlLCAidXRmOCIpKTsKICB9IGNhdGNoIChlcnJvcikgewogICAgY29uc3QgYmFja3VwID0gYCR7c2V0dGluZ3NGaWxlfS5iYWsuJHtEYXRlLm5vdygpfWA7CiAgICBmcy5jb3B5RmlsZVN5bmMoc2V0dGluZ3NGaWxlLCBiYWNrdXApOwogICAgY29uc29sZS53YXJuKGBFeGlzdGluZyBzZXR0aW5ncyB3ZXJlIGludmFsaWQgSlNPTi4gQmFja2VkIHVwIHRvICR7YmFja3VwfWApOwogIH0KfQoKc2V0dGluZ3MuZW52ID0gewogIC4uLihzZXR0aW5ncy5lbnYgfHwge30pLAogIEFOVEhST1BJQ19CQVNFX1VSTDogYmFzZVVybCwKICBBTlRIUk9QSUNfTU9ERUw6IG1vZGVsLAogIEFOVEhST1BJQ19ERUZBVUxUX0hBSUtVX01PREVMOiBtb2RlbCwKICBBTlRIUk9QSUNfREVGQVVMVF9TT05ORVRfTU9ERUw6IG1vZGVsLAogIEFOVEhST1BJQ19ERUZBVUxUX09QVVNfTU9ERUw6IG1vZGVsLAp9OwoKaWYgKHNldHRpbmdzLmluY2x1ZGVDb0F1dGhvcmVkQnkgPT09IHVuZGVmaW5lZCkgewogIHNldHRpbmdzLmluY2x1ZGVDb0F1dGhvcmVkQnkgPSBmYWxzZTsKfQoKZnMud3JpdGVGaWxlU3luYyhzZXR0aW5nc0ZpbGUsIGAke0pTT04uc3RyaW5naWZ5KHNldHRpbmdzLCBudWxsLCAyKX1cbmAsIHsgbW9kZTogMG82MDAgfSk7CidAIHwgbm9kZQoKV3JpdGUtSG9zdCAiQ2xhdWRlIENvZGUgTWlNbyBtb2RlbCBzZXQgdG86ICRNb2RlbCIKV3JpdGUtSG9zdCAiUnVuOiBjbGF1ZGUiCg=="
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

Install-ClaudeCodeNative

if (-not $SkipMimoConfig) {
  $settingsDir = Join-Path $HOME ".claude"
  $settingsFile = Join-Path $settingsDir "settings.json"
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

  Write-Host "Done. Claude Code is configured for MiMo model: $Model"
}
else {
  Write-Host "Skipped MiMo API configuration."
}

Install-MimoSwitcher
Install-ProviderSwitcher
Install-ProviderKeySetter

Write-Host ""
Write-Host "Restart CMD/PowerShell if new commands are not recognized."
Write-Host "Run: claude"
Write-Host "Switch provider/model with: claude-provider mimo flash"
Write-Host "Switch provider/model with: claude-provider mimo pro"
Write-Host "Switch provider/model with: claude-provider mimo omni"
Write-Host "Switch provider/model with: claude-provider deepseek pro"
