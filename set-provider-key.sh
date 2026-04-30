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
export PROVIDER_FILE
export SETTINGS_FILE

node <<'NODE'
const fs = require("fs");

const provider = process.env.PROVIDER;
const token = process.env.TOKEN;
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

fs.writeFileSync(providerFile, `${JSON.stringify(providerConfig, null, 2)}\n`, { mode: 0o600 });

if (providerConfig.activeProvider === provider && fs.existsSync(settingsFile)) {
  const settings = readJson(settingsFile);
  settings.env = {
    ...(settings.env || {}),
    ANTHROPIC_AUTH_TOKEN: token,
  };
  fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`, { mode: 0o600 });
}
NODE

chmod 600 "${PROVIDER_FILE}" "${SETTINGS_FILE}" 2>/dev/null || true
echo "Saved API key for provider: ${PROVIDER}"
echo "If ${PROVIDER} is active, Claude Code settings were updated too."
