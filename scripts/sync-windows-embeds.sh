#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "${ROOT_DIR}" <<'PY'
import base64
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
install_path = root / "install.ps1"
install = install_path.read_text(encoding="utf-8")

replacements = {
    "Install-ProviderSwitcher": root / "switch-provider.ps1",
    "Install-ProviderKeySetter": root / "set-provider-key.ps1",
    "Install-MimoSwitcher": root / "switch-mimo.ps1",
}

for function_name, source_path in replacements.items():
    encoded = base64.b64encode(source_path.read_bytes()).decode("ascii")
    pattern = (
        rf"(function {re.escape(function_name)} \{{.*?"
        rf"\$embeddedScript = \")([A-Za-z0-9+/=]+)(\".*?"
        rf"\[System\.IO\.File\]::WriteAllText)"
    )
    install, count = re.subn(pattern, rf"\g<1>{encoded}\g<3>", install, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Could not update embedded script for {function_name}")

install_path.write_text(install, encoding="utf-8")
PY
