#!/usr/bin/env bash
set -euo pipefail

MODEL="${DEEPSEEK_MODEL:-deepseek-v4-pro}"
DEEPSEEK_BASE_URL="${DEEPSEEK_ANTHROPIC_BASE_URL:-https://api.deepseek.com/anthropic}"
SKIP_PROVIDER_CONFIG="${SKIP_PROVIDER_CONFIG:-${SKIP_MIMO_CONFIG:-0}}"

for arg in "$@"; do
  case "${arg}" in
    --skip-api-key|--skip-mimo-config)
      SKIP_PROVIDER_CONFIG="1"
      ;;
    --help|-h)
      echo "Usage: install.sh [--skip-api-key]"
      echo ""
      echo "Environment:"
      echo "  DEEPSEEK_API_KEY             DeepSeek API key"
      echo "  DEEPSEEK_MODEL               Model name, default: deepseek-v4-pro"
      echo "  DEEPSEEK_ANTHROPIC_BASE_URL  DeepSeek API base URL"
      echo "  MIMO_API_KEY                 Optional Xiaomi MiMo API key for provider switching"
      echo "  MIMO_ANTHROPIC_BASE_URL      API base URL; auto-detected for sk-/tp- keys if unset"
      echo "  SKIP_PROVIDER_CONFIG=1       Install tools only; configure API later"
      exit 0
      ;;
  esac
done

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

ensure_shell_profile_path() {
  local install_dir="$1"
  local profile_file shell_name marker

  if [[ ":${PATH}:" != *":${install_dir}:"* ]]; then
    export PATH="${install_dir}:${PATH}"
    hash -r 2>/dev/null || true
  fi

  shell_name="$(basename "${SHELL:-}")"
  case "${shell_name}" in
    zsh)
      profile_file="${HOME}/.zshrc"
      ;;
    bash)
      if [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]; then
        profile_file="${HOME}/.bash_profile"
      else
        profile_file="${HOME}/.bashrc"
      fi
      ;;
    *)
      profile_file="${HOME}/.profile"
      ;;
  esac

  marker="claude-code-mimo PATH"
  if [ -f "${profile_file}" ] && grep -Fq "${install_dir}" "${profile_file}"; then
    echo "PATH already includes ${install_dir} in ${profile_file}"
    return
  fi

  {
    echo ""
    echo "# ${marker}"
    echo "export PATH=\"${install_dir}:\$PATH\""
  } >> "${profile_file}"

  echo "Added ${install_dir} to ${profile_file}"
}

install_provider_switcher() {
  local install_dir target source_url

  install_dir="${HOME}/.local/bin"
  target="${install_dir}/claude-provider"
  source_url="${PROVIDER_SWITCHER_URL:-https://github.com/BH4ME/claude-code-mimo-deepseek-installer/releases/latest/download/switch-provider.sh}"

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
  ensure_shell_profile_path "${install_dir}"
}

install_provider_key_setter() {
  local install_dir target source_url

  install_dir="${HOME}/.local/bin"
  target="${install_dir}/claude-provider-key"
  source_url="${PROVIDER_KEY_SETTER_URL:-https://github.com/BH4ME/claude-code-mimo-deepseek-installer/releases/latest/download/set-provider-key.sh}"

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
  ensure_shell_profile_path "${install_dir}"
}

install_mimo_switcher() {
  local install_dir target source_url

  install_dir="${HOME}/.local/bin"
  target="${install_dir}/claude-mimo"
  source_url="${MIMO_SWITCHER_URL:-https://github.com/BH4ME/claude-code-mimo-deepseek-installer/releases/latest/download/switch-mimo.sh}"

  mkdir -p "${install_dir}"

  if [ -f "./switch-mimo.sh" ]; then
    cp "./switch-mimo.sh" "${target}"
  else
    curl -fsSL "${source_url}" -o "${target}"
  fi

  chmod +x "${target}"
  echo "MiMo model switcher installed to: ${target}"
  echo "Switch models with: ${target} flash"
  ensure_shell_profile_path "${install_dir}"
}

write_initial_config() {
  if command -v python3 >/dev/null 2>&1; then
    python3 <<'PY'
import json
import os
import shutil
import time

settings_file = os.environ["SETTINGS_FILE"]
claude_json_file = os.environ["CLAUDE_JSON_FILE"]
provider_file = os.environ["PROVIDER_FILE"]
token = os.environ["DEEPSEEK_API_KEY"]
mimo_token = os.environ.get("MIMO_API_KEY", "")
model = os.environ["MODEL"]
base_url = os.environ["DEEPSEEK_BASE_URL"]
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
    "ANTHROPIC_API_KEY": token,
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
provider_config["providers"]["deepseek"] = {
    **provider_config["providers"].get("deepseek", {}),
    "baseUrl": deepseek_base_url,
    "authToken": token,
}
if mimo_token:
    provider_config["providers"]["mimo"] = {
        **provider_config["providers"].get("mimo", {}),
        "baseUrl": os.environ["MIMO_BASE_URL"],
        "authToken": mimo_token,
    }
provider_config["activeProvider"] = "deepseek"
provider_config["activeModel"] = model
with open(provider_file, "w", encoding="utf-8") as handle:
    json.dump(provider_config, handle, indent=2)
    handle.write("\n")

claude_json = read_json(claude_json_file, "Claude Code global config")
claude_json["hasCompletedOnboarding"] = True
with open(claude_json_file, "w", encoding="utf-8") as handle:
    json.dump(claude_json, handle, indent=2)
    handle.write("\n")
PY
    return
  fi

  if command -v node >/dev/null 2>&1; then
    node <<'NODE'
const fs = require("fs");

const settingsFile = process.env.SETTINGS_FILE;
const claudeJsonFile = process.env.CLAUDE_JSON_FILE;
const providerFile = process.env.PROVIDER_FILE;
const token = process.env.DEEPSEEK_API_KEY;
const mimoToken = process.env.MIMO_API_KEY || "";
const model = process.env.MODEL;
const baseUrl = process.env.DEEPSEEK_BASE_URL;
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
  ANTHROPIC_API_KEY: token,
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
providerConfig.providers.deepseek = {
  ...(providerConfig.providers.deepseek || {}),
  baseUrl: deepseekBaseUrl,
  authToken: token,
};
if (mimoToken) {
  providerConfig.providers.mimo = {
    ...(providerConfig.providers.mimo || {}),
    baseUrl: process.env.MIMO_BASE_URL,
    authToken: mimoToken,
  };
}
providerConfig.activeProvider = "deepseek";
providerConfig.activeModel = model;
fs.writeFileSync(providerFile, `${JSON.stringify(providerConfig, null, 2)}\n`, { mode: 0o600 });

const claudeJson = readJson(claudeJsonFile, "Claude Code global config");
claudeJson.hasCompletedOnboarding = true;
fs.writeFileSync(claudeJsonFile, `${JSON.stringify(claudeJson, null, 2)}\n`, { mode: 0o600 });
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
    "ANTHROPIC_BASE_URL": "${DEEPSEEK_BASE_URL}",
    "ANTHROPIC_API_KEY": "${DEEPSEEK_API_KEY}",
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
    "deepseek": {
      "baseUrl": "${DEEPSEEK_BASE_URL}",
      "authToken": "${DEEPSEEK_API_KEY}"
    }
  },
  "activeProvider": "deepseek",
  "activeModel": "${MODEL}"
}
EOF
  if [ -n "${MIMO_API_KEY:-}" ]; then
    python3 - <<'PY'
import json
import os

provider_file = os.environ["PROVIDER_FILE"]
mimo_token = os.environ["MIMO_API_KEY"]
mimo_base_url = os.environ["MIMO_BASE_URL"]
with open(provider_file, encoding="utf-8") as handle:
    data = json.load(handle)
data.setdefault("providers", {})
data["providers"]["mimo"] = {
    **data["providers"].get("mimo", {}),
    "baseUrl": mimo_base_url,
    "authToken": mimo_token,
}
with open(provider_file, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
  fi
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

  if npm_supports_claude_code && npm_install_claude_code; then
    return
  fi

  echo "System npm could not install Claude Code. Installing a user-local Node.js runtime..."
  install_user_node

  if npm_supports_claude_code && npm_install_claude_code; then
    return
  fi

  echo "Could not install Claude Code automatically." >&2
  echo "The official installer may be blocked, and npm could not install Claude Code." >&2
  echo "Install Node.js 18+ first, then rerun this script, or rerun with a network/proxy that can access https://claude.ai/install.sh." >&2
  exit 1
}

npm_supports_claude_code() {
  command -v node >/dev/null 2>&1 || return 1
  command -v npm >/dev/null 2>&1 || return 1

  local major
  major="$(node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/' || echo 0)"
  case "${major}" in
    ''|*[!0-9]*)
      major="0"
      ;;
  esac
  [ "${major}" -ge 18 ]
}

npm_install_claude_code() {
  local npm_prefix
  npm_prefix="${NPM_GLOBAL_PREFIX:-${HOME}/.local}"

  mkdir -p "${npm_prefix}/bin"
  npm config set prefix "${npm_prefix}" >/dev/null 2>&1 || true
  npm install -g @anthropic-ai/claude-code

  ensure_shell_profile_path "${npm_prefix}/bin"
}

install_user_node() {
  local os arch version base_dir tarball url strip_dir

  os="$(uname -s)"
  arch="$(uname -m)"
  version="${NODE_VERSION_FOR_CLAUDE:-22.11.0}"
  base_dir="${HOME}/.local/share/claude-code-mimo/node"
  mkdir -p "${base_dir}" "${HOME}/.local/bin"

  case "${os}" in
    Linux) os="linux" ;;
    Darwin) os="darwin" ;;
    *)
      echo "Unsupported OS for user-local Node.js install: ${os}" >&2
      return 1
      ;;
  esac

  case "${arch}" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      echo "Unsupported architecture for user-local Node.js install: ${arch}" >&2
      return 1
      ;;
  esac

  strip_dir="node-v${version}-${os}-${arch}"
  tarball="$(mktemp)"
  url="https://nodejs.org/dist/v${version}/${strip_dir}.tar.xz"

  echo "Downloading Node.js ${version} from ${url}"
  curl -fsSL "${url}" -o "${tarball}"
  rm -rf "${base_dir}/${strip_dir}"
  tar -xJf "${tarball}" -C "${base_dir}"
  rm -f "${tarball}"

  ln -sf "${base_dir}/${strip_dir}/bin/node" "${HOME}/.local/bin/node"
  ln -sf "${base_dir}/${strip_dir}/bin/npm" "${HOME}/.local/bin/npm"
  ln -sf "${base_dir}/${strip_dir}/bin/npx" "${HOME}/.local/bin/npx"
  export PATH="${HOME}/.local/bin:${PATH}"
  export NPM_GLOBAL_PREFIX="${HOME}/.local"
  ensure_shell_profile_path "${HOME}/.local/bin"
  hash -r 2>/dev/null || true

  echo "User-local Node.js installed to: ${base_dir}/${strip_dir}"
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

if [ "${SKIP_PROVIDER_CONFIG}" != "1" ] && [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  if [ ! -r /dev/tty ]; then
    echo "DeepSeek API key is required. Set DEEPSEEK_API_KEY for non-interactive installs."
    echo "Or set SKIP_PROVIDER_CONFIG=1 to install Claude Code and configure the API later."
    exit 1
  fi
  printf "Enter your DeepSeek API key: "
  stty -echo < /dev/tty
  read -r DEEPSEEK_API_KEY < /dev/tty
  stty echo < /dev/tty
  printf "\n"
fi

if [ "${SKIP_PROVIDER_CONFIG}" != "1" ] && [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "DeepSeek API key is required."
  exit 1
fi

MIMO_BASE_URL="$(get_mimo_base_url "${MIMO_API_KEY:-}")"

echo "Installing or updating Claude Code..."
install_claude_code

if [ "${SKIP_PROVIDER_CONFIG}" != "1" ]; then
  SETTINGS_DIR="${HOME}/.claude"
  SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
  CLAUDE_JSON_FILE="${HOME}/.claude.json"
  PROVIDER_FILE="${SETTINGS_DIR}/provider-switch.json"
  mkdir -p "${SETTINGS_DIR}"

  export SETTINGS_FILE
  export CLAUDE_JSON_FILE
  export PROVIDER_FILE
  export MIMO_API_KEY="${MIMO_API_KEY:-}"
  export DEEPSEEK_API_KEY
  export MODEL
  export MIMO_BASE_URL
  export DEEPSEEK_BASE_URL

  write_initial_config

  chmod 600 "${SETTINGS_FILE}" "${CLAUDE_JSON_FILE}" "${PROVIDER_FILE}" || true

  echo "Done. Claude Code is configured for DeepSeek model: ${MODEL}"
else
  echo "Skipped provider API configuration."
fi
echo "Run: claude"

install_mimo_switcher
install_provider_switcher
install_provider_key_setter
