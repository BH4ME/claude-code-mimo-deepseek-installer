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
  { $_ -in @("pro", "v2-pro", "mimo-v2-pro") } { $Model = "mimo-v2-pro"; break }
  { $_ -in @("omni", "v2-omni", "mimo-v2-omni") } { $Model = "mimo-v2-omni"; break }
  { $_ -in @("--help", "-h", "") } {
    Write-Host "Usage: .\switch-mimo.ps1 <flash|pro|omni|model-name>"
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

@'
const fs = require("fs");

const settingsFile = process.env.CLAUDE_SETTINGS_FILE;
const model = process.env.MIMO_MODEL_EFFECTIVE;
const baseUrl = process.env.MIMO_BASE_URL_EFFECTIVE;

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

Write-Host "Claude Code MiMo model set to: $Model"
Write-Host "Run: claude"
