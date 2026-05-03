#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "${SCRIPT_DIR}/claude-provider" ]; then
  exec "${SCRIPT_DIR}/claude-provider" mimo "$@"
fi
if command -v claude-provider >/dev/null 2>&1; then
  exec claude-provider mimo "$@"
fi

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

if command -v python3 >/dev/null 2>&1; then
  python3 <<'PY'
import json
import os
import shutil
import time

settings_file = os.environ["SETTINGS_FILE"]
model = os.environ["MODEL"]
base_url = os.environ["BASE_URL"]

settings = {}
if os.path.exists(settings_file):
    try:
        with open(settings_file, encoding="utf-8") as handle:
            settings = json.load(handle)
    except Exception:
        backup = f"{settings_file}.bak.{int(time.time() * 1000)}"
        shutil.copy2(settings_file, backup)
        print(f"Existing settings were invalid JSON. Backed up to {backup}")

settings["env"] = {
    **settings.get("env", {}),
    "ANTHROPIC_BASE_URL": base_url,
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
else
  echo "Neither python3 nor node is available. Cannot update JSON settings safely." >&2
  exit 1
fi

chmod 600 "${SETTINGS_FILE}" || true
echo "Claude Code MiMo model set to: ${MODEL}"
echo "Run: claude"
