#!/usr/bin/env bash
#
# BindCaptain test driver — run from anywhere (cd's to repo root).
#
# Usage:
#   tests/driver.sh                    # default suite, skips container build (fast)
#   tests/driver.sh --full             # suite including container build/startup
#   tests/driver.sh --live             # suite + live bc.* CRUD (needs BC_HOST or --host)
#   tests/driver.sh --live-only        # only live CRUD script
#   tests/driver.sh --live --host root@wolfman.reonetlabs.us
#   tests/driver.sh -- --help          # pass flags to run-tests.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

SKIP_CONTAINER=1
LIVE=0
LIVE_ONLY=0
HOST="${BC_HOST:-}"
PASS_THROUGH=()

usage() {
  cat <<'EOF'
BindCaptain test driver (runs from repo root).

  tests/driver.sh                     Default suite; skips container build (SKIP_CONTAINER_TESTS=1)
  tests/driver.sh --full              Run everything including container build/startup
  tests/driver.sh --live              Suite + live bc.* CRUD (set BC_HOST or use --host)
  tests/driver.sh --live-only         Only tests/test-bc-crud-live.sh
  tests/driver.sh --live --host root@wolfman.reonetlabs.us

  tests/driver.sh -- --help           Forward args to run-tests.sh

Environment: BC_HOST is used when set; --host overrides for this invocation.
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    --full|--no-skip-container)
      SKIP_CONTAINER=0
      shift
      ;;
    --skip-container)
      SKIP_CONTAINER=1
      shift
      ;;
    --live)
      LIVE=1
      shift
      ;;
    --live-only)
      LIVE_ONLY=1
      LIVE=1
      shift
      ;;
    --host=*)
      HOST="${1#*=}"
      shift
      ;;
    --host)
      shift
      [[ $# -eq 0 ]] && { echo "error: --host needs a value" >&2; exit 1; }
      HOST="$1"
      shift
      ;;
    --)
      shift
      PASS_THROUGH=("$@")
      break
      ;;
    *)
      echo "Unknown option: $1 (try tests/driver.sh --help)" >&2
      exit 1
      ;;
  esac
done

if [[ -n "$HOST" ]]; then
  export BC_HOST="$HOST"
fi

if [[ "$LIVE_ONLY" -eq 1 ]]; then
  export BC_LIVE_TESTS=1
  echo "[driver] BC_LIVE_TESTS=1  BC_HOST=${BC_HOST:-'(unset — local mode on DNS host)'}"
  exec bash "$SCRIPT_DIR/test-bc-crud-live.sh"
fi

if [[ "$SKIP_CONTAINER" -eq 1 ]]; then
  export SKIP_CONTAINER_TESTS=1
else
  unset SKIP_CONTAINER_TESTS 2>/dev/null || true
fi

if [[ "$LIVE" -eq 1 ]]; then
  export BC_LIVE_TESTS=1
  echo "[driver] BC_LIVE_TESTS=1  BC_HOST=${BC_HOST:-'(unset — local mode)'}"
else
  unset BC_LIVE_TESTS 2>/dev/null || true
fi

exec ./tests/run-tests.sh "${PASS_THROUGH[@]}"
