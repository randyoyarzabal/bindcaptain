#!/usr/bin/env bash
#
# Run on the BindCaptain host (as root) to:
#  1) Fix /etc/rndc.key perms in the running container.
#  2) Optionally merge rndc controls into named.conf (MERGE_NAMED=1).
#
# After first MERGE, restart: podman restart bindcaptain
#
# Usage:
#   sudo ./tools/ensure-rndc-controls.sh
#   sudo MERGE_NAMED=1 BINDCAPTAIN_CONFIG_PATH=/opt/common/.../bindcaptain ./tools/ensure-rndc-controls.sh
#
set -euo pipefail
CONTAINER_NAME="${CONTAINER_NAME:-bindcaptain}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh" 2>/dev/null || { echo "source common.sh failed"; exit 1; }
BINDCAPTAIN_CONFIG_PATH="${BINDCAPTAIN_CONFIG_PATH:-$REPO_DIR/config}"
NAMED="$BINDCAPTAIN_CONFIG_PATH/named.conf"
FRAGMENT="$REPO_DIR/config-examples/named-fragment-rndc.conf"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

if ! command -v podman &>/dev/null; then
  echo "podman not found"
  exit 1
fi

if podman ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
  podman exec "$CONTAINER_NAME" sh -c 'test -f /etc/rndc.key && chown root:named /etc/rndc.key && chmod 640 /etc/rndc.key' \
    && echo "OK: /etc/rndc.key perms in container (root:named 640)" \
    || echo "WARN: could not fix rndc key in container (container down?)"
else
  echo "WARN: container $CONTAINER_NAME is not running"
fi

if [[ "${MERGE_NAMED:-0}" == "1" ]]; then
  if [[ ! -f "$NAMED" ]]; then
    echo "ERROR: $NAMED not found (set BINDCAPTAIN_CONFIG_PATH?)"
    exit 1
  fi
  if [[ ! -f "$FRAGMENT" ]]; then
    echo "ERROR: fragment not found: $FRAGMENT"
    exit 1
  fi
  if grep -q 'inet 127.0.0.1 port 953' "$NAMED" 2>/dev/null; then
    echo "OK: named.conf already has rndc controls block"
  else
    cp -a "$NAMED" "$NAMED.bak.$(date +%Y%m%d%H%M%S)"
    MERGE=1 NAMED_FILE="$NAMED" FRAGMENT_FILE="$FRAGMENT" python3 <<'PY'
import os, sys
n = os.environ["NAMED_FILE"]
f = os.environ["FRAGMENT_FILE"]
text = open(n, "r", encoding="utf-8", errors="replace").read()
if "inet 127.0.0.1 port 953" in text:
    print("OK: already present")
    sys.exit(0)
frag = open(f, "r", encoding="utf-8", errors="replace").read()
marker = 'include "/etc/named.root.key";'
if marker in text:
    text2 = text.replace(marker, frag.strip() + "\n\n" + marker, 1)
else:
    text2 = text.rstrip() + "\n\n" + frag.strip() + "\n"
open(n, "w", encoding="utf-8").write(text2)
print("OK: merged rndc block into", n, "- restart container: podman restart", os.environ.get("CONTAINER_NAME", "bindcaptain"))
PY
  fi
fi

echo "Done."
