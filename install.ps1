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
    Invoke-WebRequest -Uri "https://github.com/BH4ME/claude-code-mimo-installer/releases/latest/download/switch-provider.ps1" -OutFile $scriptPath
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
    Invoke-WebRequest -Uri "https://github.com/BH4ME/claude-code-mimo-installer/releases/latest/download/set-provider-key.ps1" -OutFile $scriptPath
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
    Invoke-WebRequest -Uri "https://github.com/BH4ME/claude-code-mimo-installer/releases/latest/download/switch-mimo.ps1" -OutFile $scriptPath
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
  if (-not $settings.ContainsKey("env") -or -not $settings.env) {
    $settings.env = [ordered]@{}
  }

  $settings.env.ANTHROPIC_BASE_URL = $BaseUrl
  $settings.env.ANTHROPIC_AUTH_TOKEN = $env:MIMO_API_KEY
  $settings.env.ANTHROPIC_MODEL = $Model
  $settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL = $Model
  $settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL = $Model
  $settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL = $Model

  if (-not $settings.ContainsKey("includeCoAuthoredBy")) {
    $settings.includeCoAuthoredBy = $false
  }

  Write-JsonFile $settingsFile $settings

  $providerConfig = Read-JsonFile $providerFile
  if (-not $providerConfig.ContainsKey("providers") -or -not $providerConfig.providers) {
    $providerConfig.providers = [ordered]@{}
  }

  $providerConfig.providers.mimo = [ordered]@{
    baseUrl = $BaseUrl
    authToken = $env:MIMO_API_KEY
  }

  if ($env:DEEPSEEK_API_KEY) {
    $providerConfig.providers.deepseek = [ordered]@{
      baseUrl = $DeepSeekBaseUrl
      authToken = $env:DEEPSEEK_API_KEY
    }
  }

  $providerConfig.activeProvider = "mimo"
  $providerConfig.activeModel = $Model
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
Write-Host "Switch provider/model with: claude-provider deepseek pro"
