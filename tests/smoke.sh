#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

json_value() {
  local file="$1"
  local expr="$2"
  python3 - "$file" "$expr" <<'PY'
import json
import sys

path, expr = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)

value = data
for part in expr.split("."):
    value = value[part]
print(value)
PY
}

run_provider() {
  local home_dir="$1"
  shift
  HOME="${home_dir}" PATH="${BASE_PATH}" "$ROOT_DIR/switch-provider.sh" "$@"
}

run_mimo() {
  local home_dir="$1"
  shift
  HOME="${home_dir}" PATH="${BASE_PATH}" "$ROOT_DIR/switch-mimo.sh" "$@"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

case_dir="${tmp}/mimo-sk"
mkdir -p "${case_dir}"
MIMO_API_KEY="sk-test" run_provider "${case_dir}" mimo pro >/dev/null
[ "$(json_value "${case_dir}/.claude/settings.json" "env.ANTHROPIC_MODEL")" = "mimo-v2.5-pro" ] || fail "mimo pro should map to mimo-v2.5-pro"
[ "$(json_value "${case_dir}/.claude/settings.json" "env.ANTHROPIC_BASE_URL")" = "https://api.xiaomimimo.com/anthropic" ] || fail "sk MiMo key should use default API base URL"

case_dir="${tmp}/mimo-token-plan"
mkdir -p "${case_dir}"
MIMO_API_KEY="tp-test" run_provider "${case_dir}" mimo omni >/dev/null
[ "$(json_value "${case_dir}/.claude/settings.json" "env.ANTHROPIC_MODEL")" = "mimo-v2.5" ] || fail "mimo omni should map to mimo-v2.5"
[ "$(json_value "${case_dir}/.claude/settings.json" "env.ANTHROPIC_BASE_URL")" = "https://token-plan-cn.xiaomimimo.com/anthropic" ] || fail "tp MiMo key should use token-plan base URL"

case_dir="${tmp}/deepseek"
mkdir -p "${case_dir}"
DEEPSEEK_API_KEY="sk-deepseek" run_provider "${case_dir}" deepseek pro >/dev/null
[ "$(json_value "${case_dir}/.claude/settings.json" "env.ANTHROPIC_MODEL")" = "deepseek-v4-pro" ] || fail "deepseek pro should map to deepseek-v4-pro"

case_dir="${tmp}/mimo-fallback"
mkdir -p "${case_dir}"
MIMO_API_KEY="tp-test" run_mimo "${case_dir}" pro >/dev/null
[ "$(json_value "${case_dir}/.claude/settings.json" "env.ANTHROPIC_MODEL")" = "mimo-v2.5-pro" ] || fail "claude-mimo pro fallback should map to mimo-v2.5-pro"
[ "$(json_value "${case_dir}/.claude/settings.json" "env.ANTHROPIC_BASE_URL")" = "https://token-plan-cn.xiaomimimo.com/anthropic" ] || fail "claude-mimo fallback should detect token-plan base URL"

case_dir="${tmp}/missing-key"
mkdir -p "${case_dir}"
set +e
missing_output="$(HOME="${case_dir}" PATH="${BASE_PATH}" "$ROOT_DIR/switch-provider.sh" mimo pro 2>&1)"
missing_status=$?
set -e
[ "${missing_status}" -ne 0 ] || fail "missing MiMo key should fail"
case "${missing_output}" in
  *"Missing API key for mimo"*) ;;
  *) fail "missing key error should explain the missing provider key" ;;
esac

grep -q "ensure_shell_profile_path" "$ROOT_DIR/install.sh" || fail "install.sh should update shell profile PATH"
grep -q "claude-provider" "$ROOT_DIR/install.sh" || fail "install.sh should install claude-provider"

python3 - "$ROOT_DIR" <<'PY'
import base64
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
install = (root / "install.ps1").read_text(encoding="utf-8")
sources = {
    "Install-ProviderSwitcher": root / "switch-provider.ps1",
    "Install-ProviderKeySetter": root / "set-provider-key.ps1",
    "Install-MimoSwitcher": root / "switch-mimo.ps1",
}

for function_name, source_path in sources.items():
    pattern = (
        rf"function {re.escape(function_name)} \{{.*?"
        rf"\$embeddedScript = \"([A-Za-z0-9+/=]+)\""
    )
    match = re.search(pattern, install, flags=re.S)
    if not match:
        raise SystemExit(f"FAIL: missing embedded script for {function_name}")
    embedded = base64.b64decode(match.group(1)).decode("utf-8").replace("\r\n", "\n")
    source = source_path.read_text(encoding="utf-8").replace("\r\n", "\n")
    if embedded != source:
        raise SystemExit(f"FAIL: embedded script for {function_name} is out of sync")
PY

echo "Smoke tests passed."
