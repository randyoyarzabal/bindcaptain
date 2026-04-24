#!/usr/bin/env bash
#
# Live CRUD tests for bc.* (Chief plugin) against a real BindCaptain host.
#
# Requirements:
#   - BC_LIVE_TESTS=1
#   - BC_HOST set (e.g. root@wolfman.reonetlabs.us) when running from your workstation
#     (or leave BC_HOST unset on the DNS host for local-mode bc.*)
#   - SSH + sudo without password for bindcaptain paths on the target host
#
# Usage:
#   BC_LIVE_TESTS=1 BC_HOST=root@wolfman.reonetlabs.us ./tests/test-bc-crud-live.sh
#

set -eo pipefail
# Note: no 'set -u' — Chief bc.* helpers reference optional $2/$3 and must not trip unbound errors.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
export BIND_NONINTERACTIVE=1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ASSERTS=0
FAILED=0

fail() {
  echo -e "${RED}FAIL:${NC} $*" >&2
  FAILED=$((FAILED + 1))
  exit 1
}

step() {
  echo -e "${BLUE}----${NC} $*"
}

_strip_color() {
  sed 's/\x1b\[[0-9;]*m//g'
}

assert_list_contains() {
  local domain="$1"
  local needle="$2"
  local msg="${3:-list should contain $needle}"
  local out
  out=$(bc.list "$domain" 2>&1 | _strip_color || true)
  ASSERTS=$((ASSERTS + 1))
  if echo "$out" | grep -Fq "$needle"; then
    echo -e "${GREEN}  ok${NC} $msg"
  else
    echo -e "${RED}  missing${NC} $msg"
    echo "  --- bc.list $domain (excerpt) ---"
    echo "$out" | tail -40
    FAILED=$((FAILED + 1))
    exit 1
  fi
}

assert_list_lacks() {
  local domain="$1"
  local needle="$2"
  local msg="${3:-list should not contain $needle}"
  local out
  out=$(bc.list "$domain" 2>&1 | _strip_color || true)
  ASSERTS=$((ASSERTS + 1))
  if echo "$out" | grep -Fq "$needle"; then
    echo -e "${RED}  still present${NC} $msg"
    FAILED=$((FAILED + 1))
    exit 1
  fi
  echo -e "${GREEN}  ok${NC} $msg"
}

if [[ "${BC_LIVE_TESTS:-}" != "1" ]]; then
  echo "SKIP: set BC_LIVE_TESTS=1 to run live bc.* CRUD tests."
  exit 0
fi

if ! command -v ssh >/dev/null 2>&1; then
  fail "ssh is required"
fi

# shellcheck source=../chief-plugin/bc_chief-plugin.sh
source "$PROJECT_DIR/chief-plugin/bc_chief-plugin.sh"

if ! _bc_check_connection; then
  fail "Cannot reach BindCaptain host (BC_HOST=${BC_HOST:-local})"
fi

TAG="bct$(date +%s)-$$"
# Same /24 as typical wolfman lab wiring; PTR reverse zones usually include 172.25.50.0/24.
IP_A="172.25.50.240"
IP_ML="172.25.50.242"
IP_UP1="172.25.50.243"
IP_UP2="172.25.50.244"

DOMAINS=(reonetlabs.us fluxmire.io homelab.io)

echo -e "${YELLOW}Live bc.* CRUD tests${NC}  TAG=$TAG  BC_HOST=${BC_HOST:-'(local)'}"

# --- Per-zone: A (subdomain), list, delete ---
for d in "${DOMAINS[@]}"; do
  step "[$d] A record subdomain CRUD"
  fqdn="bct-a-${TAG}.${d}"
  bc.create "${fqdn}" "${IP_A}" || fail "bc.create A ${fqdn}"
  assert_list_contains "$d" "$fqdn" "A appears in bc.list $d"
  bc.delete "${fqdn}" || fail "bc.delete ${fqdn}"
  assert_list_lacks "$d" "$fqdn" "A removed from bc.list $d"
done

# --- Per-zone: multi-label hostname under apex ---
for d in "${DOMAINS[@]}"; do
  step "[$d] A record multi-label hostname"
  fqdn="bct.ml.${TAG}.${d}"
  bc.create "${fqdn}" "${IP_ML}" || fail "bc.create A ${fqdn}"
  assert_list_contains "$d" "$fqdn" "multi-label A in list"
  bc.delete "${fqdn}" || fail "bc.delete ${fqdn}"
  assert_list_lacks "$d" "$fqdn" "multi-label A removed"
done

# --- Per-zone: CNAME (create target A, then CNAME, tear down) ---
for d in "${DOMAINS[@]}"; do
  step "[$d] CNAME CRUD"
  tgt="bct-tgt-${TAG}.${d}"
  alias="bct-cn-${TAG}.${d}"
  bc.create "${tgt}" "${IP_A}" || fail "bc.create target A ${tgt}"
  bc.create_cname "${alias}" "${tgt}" || fail "bc.create_cname ${alias} -> ${tgt}"
  assert_list_contains "$d" "$alias" "CNAME in list"
  bc.delete "${alias}" CNAME || fail "bc.delete CNAME ${alias}"
  assert_list_lacks "$d" "$alias" "CNAME removed"
  bc.delete "${tgt}" || fail "bc.delete target ${tgt}"
  assert_list_lacks "$d" "$tgt" "target A removed"
done

# --- Per-zone: TXT (owner bct-txt-TAG) ---
for d in "${DOMAINS[@]}"; do
  step "[$d] TXT subdomain CRUD"
  name="bct-txt-${TAG}"
  val="v=bindcaptain-test-${TAG}"
  fqdn="${name}.${d}"
  bc.create_txt "${name}" "${d}" "${val}" || fail "bc.create_txt ${fqdn}"
  assert_list_contains "$d" "$fqdn" "TXT in list"
  bc.delete "${fqdn}" TXT || fail "bc.delete TXT ${fqdn}"
  assert_list_lacks "$d" "$fqdn" "TXT removed"
done

# --- Apex TXT (@) on each zone ---
for d in "${DOMAINS[@]}"; do
  step "[$d] apex TXT (@) CRUD"
  val="bindcaptain-apex-test=${TAG}"
  bc.create_txt "@" "${d}" "${val}" || fail "bc.create_txt @ ${d}"
  assert_list_contains "$d" "${val}" "apex TXT value in list"
  bc.delete @ "${d}" TXT || fail "bc.delete @ ${d} TXT"
  out=$(bc.list "$d" 2>&1 | _strip_color || true)
  ASSERTS=$((ASSERTS + 1))
  if echo "$out" | grep -Fq "$val"; then
    fail "apex TXT value still listed after delete"
  fi
  echo -e "${GREEN}  ok${NC} apex TXT cleared"
done

# --- Replace-style update: delete + recreate A with different IP ---
for d in "${DOMAINS[@]}"; do
  step "[$d] A replace (delete + create new IP)"
  fqdn="bct-up-${TAG}.${d}"
  bc.create "${fqdn}" "${IP_UP1}" || fail "create ${fqdn} ${IP_UP1}"
  assert_list_contains "$d" "${IP_UP1}" "first IP visible"
  bc.delete "${fqdn}" || fail "delete before replace"
  bc.create "${fqdn}" "${IP_UP2}" || fail "recreate ${fqdn} ${IP_UP2}"
  assert_list_contains "$d" "${IP_UP2}" "second IP visible"
  assert_list_lacks "$d" "${IP_UP1}" "first IP gone"
  bc.delete "${fqdn}" || fail "final delete ${fqdn}"
  assert_list_lacks "$d" "$fqdn" "fqdn gone"
done

echo
echo -e "${GREEN}All live CRUD checks passed.${NC}  (assertions: $ASSERTS, BC_HOST=${BC_HOST:-local})"
exit 0
