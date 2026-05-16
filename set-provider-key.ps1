$ErrorActionPreference = "Stop"

$ProviderArg = if ($args.Count -gt 0) { $args[0] } else { "" }
$TokenArg = if ($args.Count -gt 1) { $args[1] } else { "" }
$ClaudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { $HOME }
$ProviderFile = Join-Path $ClaudeHome ".claude\provider-switch.json"
$SettingsFile = Join-Path $ClaudeHome ".claude\settings.json"

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

function Show-Usage {
  Write-Host "Usage:"
  Write-Host "  claude-provider-key mimo [api-key]"
  Write-Host "  claude-provider-key deepseek [api-key]"
  Write-Host ""
  Write-Host "Environment:"
  Write-Host "  MIMO_API_KEY      Xiaomi MiMo API key"
  Write-Host "  DEEPSEEK_API_KEY  DeepSeek API key"
}

switch ($ProviderArg) {
  { $_ -in @("mimo", "xiaomi-mimo") } {
    $Provider = "mimo"
    $Token = if ($TokenArg) { $TokenArg } elseif ($env:MIMO_API_KEY) { $env:MIMO_API_KEY } else { "" }
    break
  }
  { $_ -in @("deepseek", "ds") } {
    $Provider = "deepseek"
    $Token = if ($TokenArg) { $TokenArg } elseif ($env:DEEPSEEK_API_KEY) { $env:DEEPSEEK_API_KEY } else { "" }
    break
  }
  { $_ -in @("--help", "-h", "") } {
    Show-Usage
    exit 0
  }
  default {
    throw "Unknown provider: $ProviderArg. Use: mimo or deepseek"
  }
}

if (-not $Token) {
  $secureKey = Read-Host "Enter $Provider API key" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
  try {
    $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

if (-not $Token) {
  throw "API key is required."
}

$settingsDir = Split-Path -Parent $ProviderFile
New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null

$env:CLAUDE_KEY_PROVIDER = $Provider
$env:CLAUDE_KEY_TOKEN = $Token
$env:CLAUDE_KEY_BASE_URL = if ($Provider -eq "mimo") { Get-MimoBaseUrl $Token } else { "" }
$env:CLAUDE_PROVIDER_FILE = $ProviderFile
$env:CLAUDE_SETTINGS_FILE = $SettingsFile

@'
const fs = require("fs");

const provider = process.env.CLAUDE_KEY_PROVIDER;
const token = process.env.CLAUDE_KEY_TOKEN;
const baseUrl = process.env.CLAUDE_KEY_BASE_URL || "";
const providerFile = process.env.CLAUDE_PROVIDER_FILE;
const settingsFile = process.env.CLAUDE_SETTINGS_FILE;

function readJson(file) {
  if (!fs.existsSync(file)) return {};
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    const backup = `${file}.bak.${Date.now()}`;
    fs.copyFileSync(file, backup);
    console.warn(`Existing JSON was invalid. Backed up to ${backup}`);
    return {};
  }
}

const providerConfig = readJson(providerFile);
providerConfig.providers = providerConfig.providers || {};
providerConfig.providers[provider] = {
  ...(providerConfig.providers[provider] || {}),
  authToken: token,
};
if (baseUrl) {
  providerConfig.providers[provider].baseUrl = baseUrl;
}

fs.writeFileSync(providerFile, `${JSON.stringify(providerConfig, null, 2)}\n`, { mode: 0o600 });

if (providerConfig.activeProvider === provider && fs.existsSync(settingsFile)) {
  const settings = readJson(settingsFile);
  settings.env = {
    ...(settings.env || {}),
    ANTHROPIC_API_KEY: token,
    ANTHROPIC_AUTH_TOKEN: token,
    ...(baseUrl ? { ANTHROPIC_BASE_URL: baseUrl } : {}),
  };
  fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`, { mode: 0o600 });
}
'@ | node

Write-Host "Saved API key for provider: $Provider"
Write-Host "If $Provider is active, Claude Code settings were updated too."
