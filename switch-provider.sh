#!/usr/bin/env bash
set -euo pipefail

PROVIDER_ARG="${1:-}"
MODEL_ARG="${2:-}"
SETTINGS_FILE="${HOME}/.claude/settings.json"
PROVIDER_FILE="${HOME}/.claude/provider-switch.json"

usage() {
  cat <<'USAGE'
Usage:
  claude-provider mimo <flash|pro|omni|model-name>
  claude-provider deepseek <flash|pro|model-name>

Environment:
  MIMO_API_KEY                 Xiaomi MiMo API key
  DEEPSEEK_API_KEY             DeepSeek API key
  MIMO_ANTHROPIC_BASE_URL      Default: https://api.xiaomimimo.com/anthropic
  DEEPSEEK_ANTHROPIC_BASE_URL  Default: https://api.deepseek.com/anthropic

Examples:
  claude-provider mimo flash
  claude-provider mimo pro
  claude-provider mimo omni
  DEEPSEEK_API_KEY="sk-..." claude-provider deepseek pro
  claude-provider deepseek deepseek-v4-flash
USAGE
}

case "${PROVIDER_ARG}" in
  mimo|xiaomi-mimo)
    PROVIDER="mimo"
    BASE_URL="${MIMO_ANTHROPIC_BASE_URL:-https://api.xiaomimimo.com/anthropic}"
    TOKEN="${MIMO_API_KEY:-}"
    case "${MODEL_ARG}" in
      flash|v2-flash|mimo-v2-flash|"")
        MODEL="mimo-v2-flash"
        ;;
      pro|v2-pro|mimo-v2-pro)
        MODEL="mimo-v2-pro"
        ;;
      omni|v2-omni|mimo-v2-omni)
        MODEL="mimo-v2-omni"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        MODEL="${MODEL_ARG}"
        ;;
    esac
    ;;
  deepseek|ds)
    PROVIDER="deepseek"
    BASE_URL="${DEEPSEEK_ANTHROPIC_BASE_URL:-https://api.deepseek.com/anthropic}"
    TOKEN="${DEEPSEEK_API_KEY:-}"
    case "${MODEL_ARG}" in
      flash|v4-flash|deepseek-v4-flash|"")
        MODEL="deepseek-v4-flash"
        ;;
      pro|v4-pro|deepseek-v4-pro)
        MODEL="deepseek-v4-pro"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        MODEL="${MODEL_ARG}"
        ;;
    esac
    ;;
  --help|-h|"")
    usage
    exit 0
    ;;
  *)
    echo "Unknown provider: ${PROVIDER_ARG}" >&2
    echo "Use: mimo or deepseek" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "${SETTINGS_FILE}")"

export SETTINGS_FILE
export PROVIDER_FILE
export PROVIDER
export MODEL
export BASE_URL
export TOKEN

if command -v python3 >/dev/null 2>&1; then
  python3 <<'PY'
import json
import os
import shutil
import sys
import time

settings_file = os.environ["SETTINGS_FILE"]
provider_file = os.environ["PROVIDER_FILE"]
provider = os.environ["PROVIDER"]
model = os.environ["MODEL"]
base_url = os.environ["BASE_URL"]
token_from_env = os.environ.get("TOKEN", "")

def read_json(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        backup = f"{path}.bak.{int(time.time() * 1000)}"
        shutil.copy2(path, backup)
        print(f"Existing JSON was invalid. Backed up to {backup}")
        return {}

provider_config = read_json(provider_file)
provider_config["providers"] = provider_config.get("providers", {})
provider_config["providers"][provider] = {
    **provider_config["providers"].get(provider, {}),
    "baseUrl": base_url,
}
if token_from_env:
    provider_config["providers"][provider]["authToken"] = token_from_env

token = provider_config["providers"][provider].get("authToken")
if not token:
    env_name = "MIMO_API_KEY" if provider == "mimo" else "DEEPSEEK_API_KEY"
    print(f"Missing API key for {provider}. Re-run with {env_name}=... once.", file=sys.stderr)
    sys.exit(1)

provider_config["activeProvider"] = provider
provider_config["activeModel"] = model
with open(provider_file, "w", encoding="utf-8") as handle:
    json.dump(provider_config, handle, indent=2)
    handle.write("\n")

settings = read_json(settings_file)
settings["env"] = {
    **settings.get("env", {}),
    "ANTHROPIC_BASE_URL": base_url,
    "ANTHROPIC_AUTH_TOKEN": token,
    "ANTHROPIC_MODEL": model,
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": model,
    "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
    "ANTHROPIC_DEFAULT_OPUS_MODEL": model,
}
settings.setdefault("includeCoAuthoredBy", False)
with open(settings_file, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
PY
elif command -v node >/dev/null 2>&1; then
  node <<'NODE'
const fs = require("fs");

const settingsFile = process.env.SETTINGS_FILE;
const providerFile = process.env.PROVIDER_FILE;
const provider = process.env.PROVIDER;
const model = process.env.MODEL;
const baseUrl = process.env.BASE_URL;
const tokenFromEnv = process.env.TOKEN || "";

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
NODE
else
  echo "Neither python3 nor node is available. Cannot update JSON settings safely." >&2
  exit 1
fi

chmod 600 "${SETTINGS_FILE}" "${PROVIDER_FILE}" || true
echo "Claude Code provider set to: ${PROVIDER}"
echo "Claude Code model set to: ${MODEL}"
echo "Run: claude"
