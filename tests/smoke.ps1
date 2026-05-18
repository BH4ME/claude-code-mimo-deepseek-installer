$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Assert-Equal {
  param(
    [object]$Actual,
    [object]$Expected,
    [string]$Message
  )

  if ($Actual -ne $Expected) {
    throw "$Message. Expected '$Expected', got '$Actual'."
  }
}

function Read-Json {
  param([string]$Path)
  return Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Invoke-Provider {
  param(
    [string]$HomeDir,
    [string[]]$ProviderArgs,
    [hashtable]$Env = @{}
  )

  $oldClaudeHome = $env:CLAUDE_HOME
  $oldMimoKey = $env:MIMO_API_KEY
  $oldDeepSeekKey = $env:DEEPSEEK_API_KEY
  $env:CLAUDE_HOME = $HomeDir
  $env:MIMO_API_KEY = $Env["MIMO_API_KEY"]
  $env:DEEPSEEK_API_KEY = $Env["DEEPSEEK_API_KEY"]
  try {
    & (Join-Path $RootDir "switch-provider.ps1") @ProviderArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "switch-provider.ps1 exited with $LASTEXITCODE"
    }
  }
  finally {
    $env:CLAUDE_HOME = $oldClaudeHome
    $env:MIMO_API_KEY = $oldMimoKey
    $env:DEEPSEEK_API_KEY = $oldDeepSeekKey
  }
}

function Invoke-Mimo {
  param(
    [string]$HomeDir,
    [string[]]$MimoArgs,
    [hashtable]$Env = @{}
  )

  $oldClaudeHome = $env:CLAUDE_HOME
  $oldMimoKey = $env:MIMO_API_KEY
  $env:CLAUDE_HOME = $HomeDir
  $env:MIMO_API_KEY = $Env["MIMO_API_KEY"]
  try {
    & (Join-Path $RootDir "switch-mimo.ps1") @MimoArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "switch-mimo.ps1 exited with $LASTEXITCODE"
    }
  }
  finally {
    $env:CLAUDE_HOME = $oldClaudeHome
    $env:MIMO_API_KEY = $oldMimoKey
  }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) "mimo-smoke-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  $caseDir = Join-Path $tmp "mimo-sk"
  New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
  Invoke-Provider $caseDir @("mimo", "pro") @{ MIMO_API_KEY = "sk-test" }
  $settings = Read-Json (Join-Path $caseDir ".claude\settings.json")
  Assert-Equal $settings.env.ANTHROPIC_MODEL "mimo-v2.5-pro" "mimo pro should map to mimo-v2.5-pro"
  Assert-Equal $settings.env.ANTHROPIC_BASE_URL "https://api.xiaomimimo.com/anthropic" "sk MiMo key should use default API base URL"

  $caseDir = Join-Path $tmp "mimo-token-plan"
  New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
  Invoke-Provider $caseDir @("mimo", "omni") @{ MIMO_API_KEY = "tp-test" }
  $settings = Read-Json (Join-Path $caseDir ".claude\settings.json")
  Assert-Equal $settings.env.ANTHROPIC_MODEL "mimo-v2.5" "mimo omni should map to mimo-v2.5"
  Assert-Equal $settings.env.ANTHROPIC_BASE_URL "https://token-plan-cn.xiaomimimo.com/anthropic" "tp MiMo key should use token-plan base URL"

  $caseDir = Join-Path $tmp "deepseek"
  New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
  Invoke-Provider $caseDir @("deepseek", "pro") @{ DEEPSEEK_API_KEY = "sk-deepseek" }
  $settings = Read-Json (Join-Path $caseDir ".claude\settings.json")
  Assert-Equal $settings.env.ANTHROPIC_MODEL "deepseek-v4-pro" "deepseek pro should map to deepseek-v4-pro"
  Assert-Equal $settings.env.ANTHROPIC_BASE_URL "https://api.deepseek.com/anthropic" "deepseek should use default API base URL"

  $caseDir = Join-Path $tmp "mimo-local-provider-priority"
  New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
  Invoke-Mimo $caseDir @("pro") @{ MIMO_API_KEY = "sk-test" }
  $settings = Read-Json (Join-Path $caseDir ".claude\settings.json")
  Assert-Equal $settings.env.ANTHROPIC_MODEL "mimo-v2.5-pro" "claude-mimo should use the local switch-provider.ps1"

  $installText = Get-Content -Raw -Path (Join-Path $RootDir "install.ps1")
  if ($installText -notmatch "Enter your DeepSeek API key") {
    throw "install.ps1 should prompt for DeepSeek API key by default"
  }
  if ($installText -notmatch 'activeProvider"\s*"deepseek"|activeProvider = "deepseek"') {
    throw "install.ps1 should default active provider to deepseek"
  }

  Write-Host "PowerShell smoke tests passed."
}
finally {
  Remove-Item -Recurse -Force -Path $tmp -ErrorAction SilentlyContinue
}
