#!/usr/bin/env bash
set -euo pipefail

PROVIDER_ARG="${1:-}"
MODEL_ARG="${2:-}"
SETTINGS_FILE="${HOME}/.claude/settings.json"
PROVIDER_FILE="${HOME}/.claude/provider-switch.json"

usage() {
  cat <<'USAGE'
Usage:
  claude-provider mimo <flash|model-name>
  claude-provider deepseek <flash|pro|model-name>

Environment:
  MIMO_API_KEY                 Xiaomi MiMo API key
  DEEPSEEK_API_KEY             DeepSeek API key
  MIMO_ANTHROPIC_BASE_URL      Default: https://api.xiaomimimo.com/anthropic
  DEEPSEEK_ANTHROPIC_BASE_URL  Default: https://api.deepseek.com/anthropic

Examples:
  claude-provider mimo flash
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

chmod 600 "${SETTINGS_FILE}" "${PROVIDER_FILE}" || true
echo "Claude Code provider set to: ${PROVIDER}"
echo "Claude Code model set to: ${MODEL}"
echo "Run: claude"
