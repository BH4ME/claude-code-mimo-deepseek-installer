#!/usr/bin/env bash
set -euo pipefail

PROVIDER_ARG="${1:-}"
TOKEN_ARG="${2:-}"
PROVIDER_FILE="${HOME}/.claude/provider-switch.json"
SETTINGS_FILE="${HOME}/.claude/settings.json"

usage() {
  cat <<'USAGE'
Usage:
  claude-provider-key mimo [api-key]
  claude-provider-key deepseek [api-key]

Environment:
  MIMO_API_KEY      Xiaomi MiMo API key
  DEEPSEEK_API_KEY  DeepSeek API key

Examples:
  claude-provider-key mimo
  claude-provider-key deepseek sk-...
  DEEPSEEK_API_KEY="sk-..." claude-provider-key deepseek
USAGE
}

get_mimo_base_url() {
  local token="${1:-}"
  if [ -n "${MIMO_ANTHROPIC_BASE_URL:-}" ]; then
    printf '%s\n' "${MIMO_ANTHROPIC_BASE_URL}"
  elif [[ "${token}" == tp-* ]]; then
    printf '%s\n' "https://token-plan-cn.xiaomimimo.com/anthropic"
  else
    printf '%s\n' "https://api.xiaomimimo.com/anthropic"
  fi
}

case "${PROVIDER_ARG}" in
  mimo|xiaomi-mimo)
    PROVIDER="mimo"
    TOKEN="${TOKEN_ARG:-${MIMO_API_KEY:-}}"
    ;;
  deepseek|ds)
    PROVIDER="deepseek"
    TOKEN="${TOKEN_ARG:-${DEEPSEEK_API_KEY:-}}"
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

if [ -z "${TOKEN}" ]; then
  if [ ! -r /dev/tty ]; then
    echo "API key is required. Pass it as an argument or environment variable." >&2
    exit 1
  fi
  printf "Enter ${PROVIDER} API key: "
  stty -echo < /dev/tty
  read -r TOKEN < /dev/tty
  stty echo < /dev/tty
  printf "\n"
fi

if [ -z "${TOKEN}" ]; then
  echo "API key is required." >&2
  exit 1
fi

mkdir -p "$(dirname "${PROVIDER_FILE}")"

export PROVIDER
export TOKEN
if [ "${PROVIDER}" = "mimo" ]; then
  BASE_URL="$(get_mimo_base_url "${TOKEN}")"
else
  BASE_URL=""
fi
export BASE_URL
export PROVIDER_FILE
export SETTINGS_FILE

if command -v python3 >/dev/null 2>&1; then
  python3 <<'PY'
import json
import os
import shutil
import time

provider = os.environ["PROVIDER"]
token = os.environ["TOKEN"]
base_url = os.environ.get("BASE_URL", "")
provider_file = os.environ["PROVIDER_FILE"]
settings_file = os.environ["SETTINGS_FILE"]

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
    "authToken": token,
}
if base_url:
    provider_config["providers"][provider]["baseUrl"] = base_url

with open(provider_file, "w", encoding="utf-8") as handle:
    json.dump(provider_config, handle, indent=2)
    handle.write("\n")

if provider_config.get("activeProvider") == provider and os.path.exists(settings_file):
    settings = read_json(settings_file)
    settings["env"] = {
        **settings.get("env", {}),
        "ANTHROPIC_API_KEY": token,
    }
    settings["env"].pop("ANTHROPIC_AUTH_TOKEN", None)
    if base_url:
        settings["env"]["ANTHROPIC_BASE_URL"] = base_url
    with open(settings_file, "w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")
PY
elif command -v node >/dev/null 2>&1; then
  node <<'NODE'
const fs = require("fs");

const provider = process.env.PROVIDER;
const token = process.env.TOKEN;
const baseUrl = process.env.BASE_URL || "";
const providerFile = process.env.PROVIDER_FILE;
const settingsFile = process.env.SETTINGS_FILE;

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
  };
  delete settings.env.ANTHROPIC_AUTH_TOKEN;
  if (baseUrl) {
    settings.env.ANTHROPIC_BASE_URL = baseUrl;
  }
  fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`, { mode: 0o600 });
}
NODE
else
  echo "Neither python3 nor node is available. Cannot update JSON settings safely." >&2
  exit 1
fi

chmod 600 "${PROVIDER_FILE}" "${SETTINGS_FILE}" 2>/dev/null || true
echo "Saved API key for provider: ${PROVIDER}"
echo "If ${PROVIDER} is active, Claude Code settings were updated too."
