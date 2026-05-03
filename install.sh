#!/usr/bin/env bash
set -euo pipefail

MODEL="${MIMO_MODEL:-mimo-v2-flash}"
BASE_URL="${MIMO_ANTHROPIC_BASE_URL:-https://api.xiaomimimo.com/anthropic}"
DEEPSEEK_BASE_URL="${DEEPSEEK_ANTHROPIC_BASE_URL:-https://api.deepseek.com/anthropic}"
SKIP_MIMO_CONFIG="${SKIP_MIMO_CONFIG:-0}"

for arg in "$@"; do
  case "${arg}" in
    --skip-api-key|--skip-mimo-config)
      SKIP_MIMO_CONFIG="1"
      ;;
    --help|-h)
      echo "Usage: install.sh [--skip-api-key]"
      echo ""
      echo "Environment:"
      echo "  MIMO_API_KEY                 Xiaomi MiMo API key"
      echo "  MIMO_MODEL                   Model name, default: mimo-v2-flash"
      echo "  MIMO_ANTHROPIC_BASE_URL      API base URL"
      echo "  DEEPSEEK_API_KEY             Optional DeepSeek API key for provider switching"
      echo "  DEEPSEEK_ANTHROPIC_BASE_URL  DeepSeek API base URL"
      echo "  SKIP_MIMO_CONFIG=1           Install tools only; configure API later"
      exit 0
      ;;
  esac
done

install_provider_switcher() {
  local install_dir target source_url

  install_dir="${HOME}/.local/bin"
  target="${install_dir}/claude-provider"
  source_url="${PROVIDER_SWITCHER_URL:-https://github.com/BH4ME/claude-code-mimo-installer/releases/latest/download/switch-provider.sh}"

  mkdir -p "${install_dir}"

  if [ -f "./switch-provider.sh" ]; then
    cp "./switch-provider.sh" "${target}"
  else
    curl -fsSL "${source_url}" -o "${target}"
  fi

  chmod +x "${target}"
  echo "Provider switcher installed to: ${target}"
  echo "Switch provider/model with: ${target} mimo flash"
  echo "Switch provider/model with: ${target} deepseek pro"
}

install_provider_key_setter() {
  local install_dir target source_url

  install_dir="${HOME}/.local/bin"
  target="${install_dir}/claude-provider-key"
  source_url="${PROVIDER_KEY_SETTER_URL:-https://github.com/BH4ME/claude-code-mimo-installer/releases/latest/download/set-provider-key.sh}"

  mkdir -p "${install_dir}"

  if [ -f "./set-provider-key.sh" ]; then
    cp "./set-provider-key.sh" "${target}"
  else
    curl -fsSL "${source_url}" -o "${target}"
  fi

  chmod +x "${target}"
  echo "Provider API key setter installed to: ${target}"
  echo "Change API key with: ${target} mimo"
  echo "Change API key with: ${target} deepseek"
}

install_mimo_switcher() {
  local install_dir target source_url

  install_dir="${HOME}/.local/bin"
  target="${install_dir}/claude-mimo"
  source_url="${MIMO_SWITCHER_URL:-https://github.com/BH4ME/claude-code-mimo-installer/releases/latest/download/switch-mimo.sh}"

  mkdir -p "${install_dir}"

  if [ -f "./switch-mimo.sh" ]; then
    cp "./switch-mimo.sh" "${target}"
  else
    curl -fsSL "${source_url}" -o "${target}"
  fi

  chmod +x "${target}"
  echo "MiMo model switcher installed to: ${target}"
  if [[ ":${PATH}:" != *":${install_dir}:"* ]]; then
    echo "Add this to your shell profile if claude-mimo is not found:"
    echo "export PATH=\"${install_dir}:\$PATH\""
  fi
  echo "Switch models with: ${target} flash"
}

write_initial_config() {
  if command -v python3 >/dev/null 2>&1; then
    python3 <<'PY'
import json
import os
import shutil
import time

settings_file = os.environ["SETTINGS_FILE"]
provider_file = os.environ["PROVIDER_FILE"]
token = os.environ["MIMO_API_KEY"]
deepseek_token = os.environ.get("DEEPSEEK_API_KEY", "")
model = os.environ["MODEL"]
base_url = os.environ["BASE_URL"]
deepseek_base_url = os.environ["DEEPSEEK_BASE_URL"]

def read_json(path, label):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        backup = f"{path}.bak.{int(time.time() * 1000)}"
        shutil.copy2(path, backup)
        print(f"Existing {label} JSON was invalid. Backed up to {backup}")
        return {}

settings = read_json(settings_file, "settings")
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

os.makedirs(os.path.dirname(settings_file), exist_ok=True)
with open(settings_file, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")

provider_config = read_json(provider_file, "provider config")
provider_config["providers"] = provider_config.get("providers", {})
provider_config["providers"]["mimo"] = {
    **provider_config["providers"].get("mimo", {}),
    "baseUrl": base_url,
    "authToken": token,
}
if deepseek_token:
    provider_config["providers"]["deepseek"] = {
        **provider_config["providers"].get("deepseek", {}),
        "baseUrl": deepseek_base_url,
        "authToken": deepseek_token,
    }
provider_config["activeProvider"] = "mimo"
provider_config["activeModel"] = model
with open(provider_file, "w", encoding="utf-8") as handle:
    json.dump(provider_config, handle, indent=2)
    handle.write("\n")
PY
    return
  fi

  if command -v node >/dev/null 2>&1; then
    node <<'NODE'
const fs = require("fs");

const settingsFile = process.env.SETTINGS_FILE;
const providerFile = process.env.PROVIDER_FILE;
const token = process.env.MIMO_API_KEY;
const deepseekToken = process.env.DEEPSEEK_API_KEY || "";
const model = process.env.MODEL;
const baseUrl = process.env.BASE_URL;
const deepseekBaseUrl = process.env.DEEPSEEK_BASE_URL;

function readJson(file, label) {
  if (!fs.existsSync(file)) return {};
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    const backup = `${file}.bak.${Date.now()}`;
    fs.copyFileSync(file, backup);
    console.warn(`Existing ${label} JSON was invalid. Backed up to ${backup}`);
    return {};
  }
}

const settings = readJson(settingsFile, "settings");
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

const providerConfig = readJson(providerFile, "provider config");
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
NODE
    return
  fi

  echo "Neither python3 nor node is available. Writing fresh Claude Code settings."
  if [ -f "${SETTINGS_FILE}" ]; then
    cp "${SETTINGS_FILE}" "${SETTINGS_FILE}.bak.$(date +%s)"
  fi
  if [ -f "${PROVIDER_FILE}" ]; then
    cp "${PROVIDER_FILE}" "${PROVIDER_FILE}.bak.$(date +%s)"
  fi
  cat > "${SETTINGS_FILE}" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "${BASE_URL}",
    "ANTHROPIC_AUTH_TOKEN": "${MIMO_API_KEY}",
    "ANTHROPIC_MODEL": "${MODEL}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${MODEL}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${MODEL}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${MODEL}"
  },
  "includeCoAuthoredBy": false
}
EOF
  cat > "${PROVIDER_FILE}" <<EOF
{
  "providers": {
    "mimo": {
      "baseUrl": "${BASE_URL}",
      "authToken": "${MIMO_API_KEY}"
    }
  },
  "activeProvider": "mimo",
  "activeModel": "${MODEL}"
}
EOF
}

install_claude_code() {
  local installer
  installer="$(mktemp)"

  if curl -fsSL https://claude.ai/install.sh -o "${installer}" && bash "${installer}"; then
    rm -f "${installer}"
    return
  fi

  rm -f "${installer}"
  echo "Official Claude Code installer failed. Falling back to npm install..."

  if ! command -v npm >/dev/null 2>&1; then
    install_npm_for_fallback
  fi

  if command -v npm >/dev/null 2>&1; then
    npm install -g @anthropic-ai/claude-code
    return
  fi

  echo "Could not install Claude Code automatically." >&2
  echo "The official installer may be blocked, and npm is not installed." >&2
  echo "Install Node.js/npm first, then rerun this script, or rerun with a network/proxy that can access https://claude.ai/install.sh." >&2
  exit 1
}

install_npm_for_fallback() {
  echo "npm is not installed. Trying to install Node.js/npm for fallback..."

  if command -v apt-get >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y nodejs npm
    elif [ "$(id -u)" = "0" ]; then
      apt-get update
      apt-get install -y nodejs npm
    else
      echo "apt-get is available, but sudo is not installed and this user is not root." >&2
      echo "Run: su -c 'apt-get update && apt-get install -y nodejs npm'" >&2
    fi
    return
  fi

  if command -v dnf >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1; then
      sudo dnf install -y nodejs npm
    elif [ "$(id -u)" = "0" ]; then
      dnf install -y nodejs npm
    else
      echo "dnf is available, but sudo is not installed and this user is not root." >&2
      echo "Run as root: dnf install -y nodejs npm" >&2
    fi
    return
  fi

  if command -v yum >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1; then
      sudo yum install -y nodejs npm
    elif [ "$(id -u)" = "0" ]; then
      yum install -y nodejs npm
    else
      echo "yum is available, but sudo is not installed and this user is not root." >&2
      echo "Run as root: yum install -y nodejs npm" >&2
    fi
    return
  fi

  if command -v apk >/dev/null 2>&1; then
    if [ "$(id -u)" = "0" ]; then
      apk add --no-cache nodejs npm
    else
      echo "apk is available, but this user is not root." >&2
      echo "Run as root: apk add --no-cache nodejs npm" >&2
    fi
    return
  fi

  echo "No supported package manager found for automatic npm installation." >&2
}

if [ "${SKIP_MIMO_CONFIG}" != "1" ] && [ -z "${MIMO_API_KEY:-}" ]; then
  if [ ! -r /dev/tty ]; then
    echo "MiMo API key is required. Set MIMO_API_KEY for non-interactive installs."
    echo "Or set SKIP_MIMO_CONFIG=1 to install Claude Code and configure the API later."
    exit 1
  fi
  printf "Enter your MiMo API key: "
  stty -echo < /dev/tty
  read -r MIMO_API_KEY < /dev/tty
  stty echo < /dev/tty
  printf "\n"
fi

if [ "${SKIP_MIMO_CONFIG}" != "1" ] && [ -z "${MIMO_API_KEY:-}" ]; then
  echo "MiMo API key is required."
  exit 1
fi

echo "Installing or updating Claude Code..."
install_claude_code

if [ "${SKIP_MIMO_CONFIG}" != "1" ]; then
  SETTINGS_DIR="${HOME}/.claude"
  SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
  PROVIDER_FILE="${SETTINGS_DIR}/provider-switch.json"
  mkdir -p "${SETTINGS_DIR}"

  export SETTINGS_FILE
  export PROVIDER_FILE
  export MIMO_API_KEY
  export DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-}"
  export MODEL
  export BASE_URL
  export DEEPSEEK_BASE_URL

  write_initial_config

  chmod 600 "${SETTINGS_FILE}" "${PROVIDER_FILE}" || true

  echo "Done. Claude Code is configured for MiMo model: ${MODEL}"
else
  echo "Skipped MiMo API configuration."
fi
echo "Run: claude"

install_mimo_switcher
install_provider_switcher
install_provider_key_setter
