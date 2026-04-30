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
  local install_dir target

  install_dir="${HOME}/.local/bin"
  target="${install_dir}/claude-mimo"

  mkdir -p "${install_dir}"

  if [ -f "./switch-mimo.sh" ]; then
    cp "./switch-mimo.sh" "${target}"
  else
    cat > "${target}" <<'SWITCHER'
#!/usr/bin/env bash
set -euo pipefail

MODEL_ARG="${1:-}"
BASE_URL="${MIMO_ANTHROPIC_BASE_URL:-https://api.xiaomimimo.com/anthropic}"
SETTINGS_FILE="${HOME}/.claude/settings.json"

case "${MODEL_ARG}" in
  flash|v2-flash|mimo-v2-flash)
    MODEL="mimo-v2-flash"
    ;;
  --help|-h|"")
    echo "Usage: claude-mimo <flash|model-name>"
    echo ""
    echo "Switch Claude Code to a Xiaomi MiMo model."
    exit 0
    ;;
  *)
    MODEL="${MODEL_ARG}"
    ;;
esac

mkdir -p "$(dirname "${SETTINGS_FILE}")"

export SETTINGS_FILE
export MODEL
export BASE_URL

node <<'NODE'
const fs = require("fs");

const settingsFile = process.env.SETTINGS_FILE;
const model = process.env.MODEL;
const baseUrl = process.env.BASE_URL;

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
NODE

chmod 600 "${SETTINGS_FILE}" || true
echo "Claude Code MiMo model set to: ${MODEL}"
echo "Run: claude"
SWITCHER
  fi

  chmod +x "${target}"
  echo "MiMo model switcher installed to: ${target}"
  if [[ ":${PATH}:" != *":${install_dir}:"* ]]; then
    echo "Add this to your shell profile if claude-mimo is not found:"
    echo "export PATH=\"${install_dir}:\$PATH\""
  fi
  echo "Switch models with: ${target} flash"
}

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required. Install Node.js first, then rerun this installer."
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required. Install npm first, then rerun this installer."
  exit 1
fi

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
npm install -g @anthropic-ai/claude-code

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

  node <<'NODE'
const fs = require("fs");

const settingsFile = process.env.SETTINGS_FILE;
const providerFile = process.env.PROVIDER_FILE;
const token = process.env.MIMO_API_KEY;
const deepseekToken = process.env.DEEPSEEK_API_KEY || "";
const model = process.env.MODEL;
const baseUrl = process.env.BASE_URL;
const deepseekBaseUrl = process.env.DEEPSEEK_BASE_URL;

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

let providerConfig = {};
if (fs.existsSync(providerFile)) {
  try {
    providerConfig = JSON.parse(fs.readFileSync(providerFile, "utf8"));
  } catch (error) {
    const backup = `${providerFile}.bak.${Date.now()}`;
    fs.copyFileSync(providerFile, backup);
    console.warn(`Existing provider config was invalid JSON. Backed up to ${backup}`);
  }
}
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

  chmod 600 "${SETTINGS_FILE}" "${PROVIDER_FILE}" || true

  echo "Done. Claude Code is configured for MiMo model: ${MODEL}"
else
  echo "Skipped MiMo API configuration."
fi
echo "Run: claude"

install_mimo_switcher
install_provider_switcher
install_provider_key_setter
