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

function Install-ProviderSwitcher {
  $installDir = Join-Path $HOME ".claude-provider"
  $scriptPath = Join-Path $installDir "switch-provider.ps1"
  $cmdPath = Join-Path $installDir "claude-provider.cmd"
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null

  if (Test-Path ".\switch-provider.ps1") {
    Copy-Item ".\switch-provider.ps1" $scriptPath -Force
  }
  else {
    $scriptUrl = if ($env:PROVIDER_SWITCHER_PS1_URL) { $env:PROVIDER_SWITCHER_PS1_URL } else { "https://github.com/BH4ME/claude-code-mimo-installer/releases/latest/download/switch-provider.ps1" }
    Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath
  }

  if (Test-Path ".\claude-provider.cmd") {
    Copy-Item ".\claude-provider.cmd" $cmdPath -Force
  }
  else {
    Set-Content -Path $cmdPath -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0switch-provider.ps1`" %*"
  }

  $npmPrefix = (& npm config get prefix).Trim()
  if ($npmPrefix -and (Test-Path $npmPrefix)) {
    Copy-Item $scriptPath (Join-Path $npmPrefix "switch-provider.ps1") -Force
    Set-Content -Path (Join-Path $npmPrefix "claude-provider.cmd") -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0switch-provider.ps1`" %*"
  }

  Write-Host "Provider switcher installed to: $installDir"
  Write-Host "Switch provider/model with: claude-provider mimo flash"
  Write-Host "Switch provider/model with: claude-provider deepseek pro"
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
    $scriptUrl = if ($env:PROVIDER_KEY_SETTER_PS1_URL) { $env:PROVIDER_KEY_SETTER_PS1_URL } else { "https://github.com/BH4ME/claude-code-mimo-installer/releases/latest/download/set-provider-key.ps1" }
    Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath
  }

  if (Test-Path ".\claude-provider-key.cmd") {
    Copy-Item ".\claude-provider-key.cmd" $cmdPath -Force
  }
  else {
    Set-Content -Path $cmdPath -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0set-provider-key.ps1`" %*"
  }

  $npmPrefix = (& npm config get prefix).Trim()
  if ($npmPrefix -and (Test-Path $npmPrefix)) {
    Copy-Item $scriptPath (Join-Path $npmPrefix "set-provider-key.ps1") -Force
    Set-Content -Path (Join-Path $npmPrefix "claude-provider-key.cmd") -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0set-provider-key.ps1`" %*"
  }

  Write-Host "Provider API key setter installed to: $installDir"
  Write-Host "Change API key with: claude-provider-key mimo"
  Write-Host "Change API key with: claude-provider-key deepseek"
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
    Set-Content -Path $scriptPath -Encoding UTF8 -Value @'
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$providerCmd = Join-Path $scriptDir "claude-provider.cmd"
$providerPs1 = Join-Path $scriptDir "switch-provider.ps1"
if (Test-Path $providerCmd) {
  & $providerCmd mimo @args
  exit $LASTEXITCODE
}
if (Test-Path $providerPs1) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $providerPs1 mimo @args
  exit $LASTEXITCODE
}
if (Get-Command claude-provider -ErrorAction SilentlyContinue) {
  & claude-provider mimo @args
  exit $LASTEXITCODE
}

$ModelArg = if ($args.Count -gt 0) { $args[0] } else { "" }
$BaseUrl = if ($env:MIMO_ANTHROPIC_BASE_URL) { $env:MIMO_ANTHROPIC_BASE_URL } else { "https://api.xiaomimimo.com/anthropic" }

switch ($ModelArg) {
  { $_ -in @("flash", "v2-flash", "mimo-v2-flash") } { $Model = "mimo-v2-flash"; break }
  { $_ -in @("--help", "-h", "") } {
    Write-Host "Usage: .\switch-mimo.ps1 <flash|model-name>"
    Write-Host ""
    Write-Host "Switch Claude Code to a Xiaomi MiMo model."
    exit 0
  }
  default {
    $Model = $ModelArg
  }
}

$settingsDir = Join-Path $HOME ".claude"
$settingsFile = Join-Path $settingsDir "settings.json"
New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null

$env:CLAUDE_SETTINGS_FILE = $settingsFile
$env:MIMO_MODEL_EFFECTIVE = $Model
$env:MIMO_BASE_URL_EFFECTIVE = $BaseUrl

@"
const fs = require("fs");

const settingsFile = process.env.CLAUDE_SETTINGS_FILE;
const model = process.env.MIMO_MODEL_EFFECTIVE;
const baseUrl = process.env.MIMO_BASE_URL_EFFECTIVE;

let settings = {};
if (fs.existsSync(settingsFile)) {
  try {
    settings = JSON.parse(fs.readFileSync(settingsFile, "utf8"));
  } catch (error) {
    const backup = settingsFile + ".bak." + Date.now();
    fs.copyFileSync(settingsFile, backup);
    console.warn("Existing settings were invalid JSON. Backed up to " + backup);
  }
}

settings.env = {
  ...(settings.env || {}),
  ANTHROPIC_BASE_URL: baseUrl,
  ANTHROPIC_MODEL: model,
  ANTHROPIC_DEFAULT_HAIKU_MODEL: model,
  ANTHROPIC_DEFAULT_SONNET_MODEL: model,
  ANTHROPIC_DEFAULT_OPUS_MODEL: model,
};

if (settings.includeCoAuthoredBy === undefined) {
  settings.includeCoAuthoredBy = false;
}

fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + "\n", { mode: 0o600 });
"@ | node

Write-Host "Claude Code MiMo model set to: $Model"
Write-Host "Run: claude"
'@
  }

  if (Test-Path ".\claude-mimo.cmd") {
    Copy-Item ".\claude-mimo.cmd" $cmdPath -Force
  }
  else {
    Set-Content -Path $cmdPath -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0switch-mimo.ps1`" %*"
  }

  $npmPrefix = (& npm config get prefix).Trim()
  if ($npmPrefix -and (Test-Path $npmPrefix)) {
    Copy-Item $scriptPath (Join-Path $npmPrefix "switch-mimo.ps1") -Force
    Set-Content -Path (Join-Path $npmPrefix "claude-mimo.cmd") -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0switch-mimo.ps1`" %*"
  }

  Write-Host "MiMo model switcher installed to: $installDir"
  Write-Host "Switch models with: claude-mimo flash"
  Write-Host "If the command is not recognized, open a new terminal or run: $cmdPath flash"
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw "Node.js is required. Install Node.js first, then rerun this installer."
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  throw "npm is required. Install npm first, then rerun this installer."
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

Write-Host "Installing or updating Claude Code..."
npm install -g "@anthropic-ai/claude-code"

if (-not $SkipMimoConfig) {
  $settingsDir = Join-Path $HOME ".claude"
  $settingsFile = Join-Path $settingsDir "settings.json"
  $providerFile = Join-Path $settingsDir "provider-switch.json"
  New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null

  $env:CLAUDE_SETTINGS_FILE = $settingsFile
  $env:CLAUDE_PROVIDER_FILE = $providerFile
  $env:MIMO_MODEL_EFFECTIVE = $Model
  $env:MIMO_BASE_URL_EFFECTIVE = $BaseUrl
  $env:DEEPSEEK_BASE_URL_EFFECTIVE = $DeepSeekBaseUrl

  @'
const fs = require("fs");

const settingsFile = process.env.CLAUDE_SETTINGS_FILE;
const providerFile = process.env.CLAUDE_PROVIDER_FILE;
const token = process.env.MIMO_API_KEY;
const deepseekToken = process.env.DEEPSEEK_API_KEY || "";
const model = process.env.MIMO_MODEL_EFFECTIVE;
const baseUrl = process.env.MIMO_BASE_URL_EFFECTIVE;
const deepseekBaseUrl = process.env.DEEPSEEK_BASE_URL_EFFECTIVE;

let settings = {};
if (fs.existsSync(settingsFile)) {
  try {
    settings = JSON.parse(fs.readFileSync(settingsFile, "utf8"));
  } catch (error) {
    const backup = `${settingsFile}.bak.${Date.now()}`;
    fs.copyFileSync(settingsFile, backup);
    console.warn(`Existing settings were invalid JSON. Backed up to ${backup}`);
  }
}

settings.env = {
  ...(settings.env || {}),
  ANTHROPIC_BASE_URL: baseUrl,
  ANTHROPIC_AUTH_TOKEN: token,
  ANTHROPIC_MODEL: model,
  ANTHROPIC_DEFAULT_HAIKU_MODEL: model,
  ANTHROPIC_DEFAULT_SONNET_MODEL: model,
  ANTHROPIC_DEFAULT_OPUS_MODEL: model,
};

if (settings.includeCoAuthoredBy === undefined) {
  settings.includeCoAuthoredBy = false;
}

fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`, { mode: 0o600 });

let providerConfig = {};
if (fs.existsSync(providerFile)) {
  try {
    providerConfig = JSON.parse(fs.readFileSync(providerFile, "utf8"));
  } catch (error) {
    const backup = `${providerFile}.bak.${Date.now()}`;
    fs.copyFileSync(providerFile, backup);
    console.warn(`Existing provider config was invalid JSON. Backed up to ${backup}`);
  }
}
providerConfig.providers = providerConfig.providers || {};
providerConfig.providers.mimo = {
  ...(providerConfig.providers.mimo || {}),
  baseUrl,
  authToken: token,
};
if (deepseekToken) {
  providerConfig.providers.deepseek = {
    ...(providerConfig.providers.deepseek || {}),
    baseUrl: deepseekBaseUrl,
    authToken: deepseekToken,
  };
}
providerConfig.activeProvider = "mimo";
providerConfig.activeModel = model;
fs.writeFileSync(providerFile, `${JSON.stringify(providerConfig, null, 2)}\n`, { mode: 0o600 });
'@ | node

  Write-Host "Done. Claude Code is configured for MiMo model: $Model"
}
else {
  Write-Host "Skipped MiMo API configuration."
}

Write-Host "Run: claude"
Install-MimoSwitcher
Install-ProviderSwitcher
Install-ProviderKeySetter
