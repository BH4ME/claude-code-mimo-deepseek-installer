$ErrorActionPreference = "Stop"

$ProviderArg = if ($args.Count -gt 0) { $args[0] } else { "" }
$ModelArg = if ($args.Count -gt 1) { $args[1] } else { "" }
$SettingsFile = Join-Path $HOME ".claude\settings.json"
$ProviderFile = Join-Path $HOME ".claude\provider-switch.json"

function Show-Usage {
  Write-Host "Usage:"
  Write-Host "  claude-provider mimo <flash|model-name>"
  Write-Host "  claude-provider deepseek <flash|pro|model-name>"
  Write-Host ""
  Write-Host "Environment:"
  Write-Host "  MIMO_API_KEY                 Xiaomi MiMo API key"
  Write-Host "  DEEPSEEK_API_KEY             DeepSeek API key"
  Write-Host "  MIMO_ANTHROPIC_BASE_URL      Default: https://api.xiaomimimo.com/anthropic"
  Write-Host "  DEEPSEEK_ANTHROPIC_BASE_URL  Default: https://api.deepseek.com/anthropic"
}

switch ($ProviderArg) {
  { $_ -in @("mimo", "xiaomi-mimo") } {
    $Provider = "mimo"
    $BaseUrl = if ($env:MIMO_ANTHROPIC_BASE_URL) { $env:MIMO_ANTHROPIC_BASE_URL } else { "https://api.xiaomimimo.com/anthropic" }
    $Token = if ($env:MIMO_API_KEY) { $env:MIMO_API_KEY } else { "" }
    switch ($ModelArg) {
      { $_ -in @("flash", "v2-flash", "mimo-v2-flash", "") } { $Model = "mimo-v2-flash"; break }
      { $_ -in @("--help", "-h") } { Show-Usage; exit 0 }
      default { $Model = $ModelArg }
    }
    break
  }
  { $_ -in @("deepseek", "ds") } {
    $Provider = "deepseek"
    $BaseUrl = if ($env:DEEPSEEK_ANTHROPIC_BASE_URL) { $env:DEEPSEEK_ANTHROPIC_BASE_URL } else { "https://api.deepseek.com/anthropic" }
    $Token = if ($env:DEEPSEEK_API_KEY) { $env:DEEPSEEK_API_KEY } else { "" }
    switch ($ModelArg) {
      { $_ -in @("flash", "v4-flash", "deepseek-v4-flash", "") } { $Model = "deepseek-v4-flash"; break }
      { $_ -in @("pro", "v4-pro", "deepseek-v4-pro") } { $Model = "deepseek-v4-pro"; break }
      { $_ -in @("--help", "-h") } { Show-Usage; exit 0 }
      default { $Model = $ModelArg }
    }
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

$settingsDir = Split-Path -Parent $SettingsFile
New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null

$env:CLAUDE_SETTINGS_FILE = $SettingsFile
$env:CLAUDE_PROVIDER_FILE = $ProviderFile
$env:CLAUDE_PROVIDER_EFFECTIVE = $Provider
$env:CLAUDE_MODEL_EFFECTIVE = $Model
$env:CLAUDE_BASE_URL_EFFECTIVE = $BaseUrl
$env:CLAUDE_TOKEN_EFFECTIVE = $Token

@'
const fs = require("fs");

const settingsFile = process.env.CLAUDE_SETTINGS_FILE;
const providerFile = process.env.CLAUDE_PROVIDER_FILE;
const provider = process.env.CLAUDE_PROVIDER_EFFECTIVE;
const model = process.env.CLAUDE_MODEL_EFFECTIVE;
const baseUrl = process.env.CLAUDE_BASE_URL_EFFECTIVE;
const tokenFromEnv = process.env.CLAUDE_TOKEN_EFFECTIVE || "";

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
  baseUrl,
};

if (tokenFromEnv) {
  providerConfig.providers[provider].authToken = tokenFromEnv;
}

const token = providerConfig.providers[provider].authToken;
if (!token) {
  const envName = provider === "mimo" ? "MIMO_API_KEY" : "DEEPSEEK_API_KEY";
  console.error(`Missing API key for ${provider}. Re-run with ${envName}=... once.`);
  process.exit(1);
}

providerConfig.activeProvider = provider;
providerConfig.activeModel = model;
fs.writeFileSync(providerFile, `${JSON.stringify(providerConfig, null, 2)}\n`, { mode: 0o600 });

const settings = readJson(settingsFile);
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
'@ | node

Write-Host "Claude Code provider set to: $Provider"
Write-Host "Claude Code model set to: $Model"
Write-Host "Run: claude"
