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
    [string[]]$Args,
    [hashtable]$Env = @{}
  )

  $script = Join-Path $RootDir "switch-provider.ps1"
  $command = @(
    "`$HOME = '$($HomeDir.Replace("'", "''"))'",
    "`$env:HOME = `$HOME",
    "`$env:USERPROFILE = `$HOME",
    "`$env:MIMO_API_KEY = '$($Env["MIMO_API_KEY"])'",
    "`$env:DEEPSEEK_API_KEY = '$($Env["DEEPSEEK_API_KEY"])'",
    "& '$($script.Replace("'", "''"))' $($Args -join ' ')"
  ) -join "; "

  & pwsh -NoProfile -ExecutionPolicy Bypass -Command $command | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "switch-provider.ps1 exited with $LASTEXITCODE"
  }
}

function Invoke-Mimo {
  param(
    [string]$HomeDir,
    [string[]]$Args,
    [hashtable]$Env = @{}
  )

  $script = Join-Path $RootDir "switch-mimo.ps1"
  $command = @(
    "`$HOME = '$($HomeDir.Replace("'", "''"))'",
    "`$env:HOME = `$HOME",
    "`$env:USERPROFILE = `$HOME",
    "`$env:MIMO_API_KEY = '$($Env["MIMO_API_KEY"])'",
    "& '$($script.Replace("'", "''"))' $($Args -join ' ')"
  ) -join "; "

  & pwsh -NoProfile -ExecutionPolicy Bypass -Command $command | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "switch-mimo.ps1 exited with $LASTEXITCODE"
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

  $caseDir = Join-Path $tmp "mimo-local-provider-priority"
  New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
  Invoke-Mimo $caseDir @("pro") @{ MIMO_API_KEY = "sk-test" }
  $settings = Read-Json (Join-Path $caseDir ".claude\settings.json")
  Assert-Equal $settings.env.ANTHROPIC_MODEL "mimo-v2.5-pro" "claude-mimo should use the local switch-provider.ps1"

  Write-Host "PowerShell smoke tests passed."
}
finally {
  Remove-Item -Recurse -Force -Path $tmp -ErrorAction SilentlyContinue
}
