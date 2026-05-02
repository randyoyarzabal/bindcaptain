#!/usr/bin/env bash
#
# ═══════════════════════════════════════════════════════════════════════════════
# Chief plugin: bc (BindCaptain) — Remote control for BindCaptain
# ═══════════════════════════════════════════════════════════════════════════════
#
# DESCRIPTION
#   Reusable Chief plugin that controls a remote BindCaptain installation over SSH.
#   Use it from your local machine to manage DNS records, service, and config on
#   a server where BindCaptain is installed (e.g. a DNS host in your network).
#
#   Example: BindCaptain runs on a server (e.g. dns.example.com); you load this plugin locally
#   in Chief and run bc.create, bc.list, etc.; commands are executed on the
#   remote host via SSH.
#
# CHIEF (separate project)
#   Chief is a separate shell framework that loads plugins like this one.
#   For what Chief is, how to install it, and how to use plugins, see:
#     https://github.com/randyoyarzabal/chief
#
# PREREQUISITES
#   - Chief (see GitHub link above) or any shell that can source this script.
#   - SSH access to the remote host as a user that can run sudo (typically root).
#   - Remote host: BindCaptain installed (e.g. under /opt/bindcaptain) with
#     bindcaptain_manager.sh and systemd service "bindcaptain" (if using
#     bc.start/stop/restart/status).
#   - SSH key-based auth recommended (no password prompt for automation).
#
# CONFIGURATION (set before sourcing or edit below)
#   BC_HOST    - Optional. If set (e.g. root@dns.example.com), commands run over SSH.
#                If unset or empty, commands run on this machine (Chief on the DNS host).
#                Legacy placeholder root@your-bindcaptain-host is treated as unset.
#   BC_MANAGER - Absolute path to bindcaptain_manager.sh (default below).
#
#   To override: export BC_HOST and/or BC_MANAGER before loading the plugin, or
#   copy this file and change the default values below.
#
# INSTALLATION IN CHIEF
#   Ensure this file is installed as a Chief user plugin named "bc" (e.g. so
#   Chief loads it as the bc plugin). Edit with: chief.plugin bc
#   See Chief GitHub (link above) for plugin installation details.
#   After changing this file or if bc.* is missing in an open shell: chief.reload
#
# COMMANDS (see bc.help after loading)
#   bc.create, bc.create_cname, bc.create_txt  - Create DNS records
#   bc.delete, bc.list                         - Delete / list records
#   bc.refresh, bc.sync_ptr                    - Refresh config / PTR rebuild from A records
#   bc.git_refresh                             - Update from Git
#   bc.status, bc.start, bc.stop, bc.restart  - Service control
#   bc.ssh, bc.help                            - SSH to host / show help
#
# See also: BindCaptain docs/chief-remote-plugin.md
#
# ═══════════════════════════════════════════════════════════════════════════════

# Block interactive execution
if [[ $0 = $BASH_SOURCE ]]; then
  echo "Error: $0 (Chief user plugin) must be sourced; not executed interactively."
  exit 1
fi

# -----------------------------------------------------------------------------
# Configuration (customize for your BindCaptain host)
# -----------------------------------------------------------------------------
BC_HOST="${BC_HOST:-}"
# Older copies shipped a fake host; treat as "run locally" so Chief on the DNS box works.
[[ "$BC_HOST" == "root@your-bindcaptain-host" ]] && BC_HOST=""
BC_MANAGER="${BC_MANAGER:-/opt/bindcaptain/tools/bindcaptain_manager.sh}"

# Plugin version. Should track the BindCaptain repo's VERSION file; surfaced
# in bc.help and the load banner.
BC_PLUGIN_VERSION="v1.2.0"

# Run a shell command on the BindCaptain host (SSH when BC_HOST is set, else this machine).
_bc_ssh() {
  if [[ -n "$BC_HOST" ]]; then
    ssh -q "$BC_HOST" "$@"
  else
    bash -c "$*"
  fi
}

_bc_check_connection() {
  if [[ -n "$BC_HOST" ]]; then
    if ! ssh -q -o ConnectTimeout=3 "$BC_HOST" "exit" 2>/dev/null; then
      echo "✗ Error: Cannot connect to $BC_HOST"
      echo "  Ensure the host is reachable and SSH (e.g. key-based) is configured."
      echo "  To run on this machine only, unset BC_HOST before loading the plugin."
      return 1
    fi
    return 0
  fi
  if [[ ! -r "$BC_MANAGER" ]]; then
    echo "✗ Error: Local mode (BC_HOST unset) but BC_MANAGER is missing or unreadable:"
    echo "  $BC_MANAGER"
    return 1
  fi
  return 0
}

# Colors for help (same scheme as bindcaptain_manager.sh)
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Output normalization helpers
#
# These wrap the verbose, colorized output of bindcaptain_manager.sh into a
# concise human-friendly summary or a JSON object suitable for programmatic
# consumption (especially over SSH).
# -----------------------------------------------------------------------------

# Strip ANSI escape sequences from input. Reads stdin, writes stdout.
_bc_strip_ansi() {
  sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

# Escape a string for safe embedding inside a JSON double-quoted value.
_bc_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Emit a JSON record summary on stdout.
# Args (all positional, may be empty strings):
#   $1 status        success|error|warning
#   $2 action        create|update|delete
#   $3 type          A|CNAME|TXT
#   $4 fqdn
#   $5 rdata         IP / target / text value
#   $6 ttl           numeric or empty
#   $7 reload        success|failed|skipped|unknown
#   $8 message       human-readable summary
#   $9 exit_code     integer
#   $10 host         BC_HOST or "local"
#   $11 raw          full captured output (will be JSON-escaped)
_bc_emit_json() {
  local status="$1" action="$2" rec_type="$3" fqdn="$4" rdata="$5" ttl="$6"
  local reload="$7" message="$8" exit_code="$9" host="${10}" raw="${11}"
  local ttl_field
  if [[ -z "$ttl" ]]; then
    ttl_field="null"
  else
    ttl_field="$ttl"
  fi
  printf '{'
  printf '"status":"%s",' "$(_bc_json_escape "$status")"
  printf '"action":"%s",' "$(_bc_json_escape "$action")"
  printf '"record":{"type":"%s","fqdn":"%s","rdata":"%s","ttl":%s},' \
    "$(_bc_json_escape "$rec_type")" \
    "$(_bc_json_escape "$fqdn")" \
    "$(_bc_json_escape "$rdata")" \
    "$ttl_field"
  printf '"reload":"%s",' "$(_bc_json_escape "$reload")"
  printf '"message":"%s",' "$(_bc_json_escape "$message")"
  printf '"exit_code":%s,' "$exit_code"
  printf '"host":"%s",' "$(_bc_json_escape "$host")"
  printf '"raw":"%s"' "$(_bc_json_escape "$raw")"
  printf '}\n'
}

# Inspect captured (ANSI-stripped) output + exit code, set globals:
#   _BC_STATUS    success|error|warning
#   _BC_MESSAGE   single-line summary distilled from the manager output
#   _BC_RELOAD    success|failed|skipped|unknown
# Reads stdin (the captured output) so callers can pipe it.
_bc_classify() {
  local exit_code="$1"
  local clean
  clean="$(cat)"
  _BC_RAW="$clean"

  # Reload status
  if grep -qE '✓.*BIND reloaded successfully|BIND reloaded via SIGHUP' <<<"$clean"; then
    _BC_RELOAD="success"
  elif grep -qE '✗.*BIND reload failed|Failed to reload BIND|rndc reload and SIGHUP both failed' <<<"$clean"; then
    _BC_RELOAD="failed"
  else
    _BC_RELOAD="unknown"
  fi

  # Pull the most informative status line. Manager uses prefixes:
  #   ✓ success / ✗ error / ⚠ warning / ℹ info
  # Walk lines, prefer the last error/success line.
  local last_success="" last_error="" last_warning=""
  while IFS= read -r line; do
    case "$line" in
      *"✗"*) last_error="${line#*✗ }" ;;
      *"✓"*) last_success="${line#*✓ }" ;;
      *"⚠"*) last_warning="${line#*⚠ }" ;;
    esac
  done <<<"$clean"

  # Exit code is the source of truth. Use it to decide success/error first;
  # status-line scraping only chooses the message.
  if [[ "$exit_code" -ne 0 ]]; then
    _BC_STATUS="error"
    _BC_MESSAGE="${last_error:-${last_warning:-Command failed (exit ${exit_code})}}"
  elif [[ -n "$last_success" ]]; then
    _BC_STATUS="success"
    _BC_MESSAGE="$last_success"
  elif [[ -n "$last_warning" ]]; then
    _BC_STATUS="warning"
    _BC_MESSAGE="$last_warning"
  elif [[ -n "$last_error" ]]; then
    # exit_code == 0 but an error line appeared: a non-fatal sub-step (e.g.
    # bc.update's pre-delete miss). Treat as success-with-note.
    _BC_STATUS="success"
    _BC_MESSAGE="completed (intermediate note: $last_error)"
  else
    _BC_STATUS="success"
    _BC_MESSAGE="Completed (no status line emitted)"
  fi
}

# Print a compact human-friendly summary block.
# Args: action, type, fqdn, rdata, ttl
_bc_emit_summary() {
  local action="$1" rec_type="$2" fqdn="$3" rdata="$4" ttl="$5"
  local host_label
  if [[ -n "$BC_HOST" ]]; then
    host_label="$BC_HOST"
  else
    host_label="local"
  fi

  local icon color
  case "$_BC_STATUS" in
    success) icon="✓"; color="$GREEN" ;;
    warning) icon="⚠"; color="$YELLOW" ;;
    error)   icon="✗"; color="$RED" ;;
    *)       icon="•"; color="$NC" ;;
  esac

  # Header: include "<TYPE> record" only when we have record context
  if [[ -n "$rec_type" ]]; then
    echo -e "${color}${icon} ${action^} ${rec_type} record: ${_BC_STATUS}${NC}"
  else
    echo -e "${color}${icon} ${action^}: ${_BC_STATUS}${NC}"
  fi
  echo "  Host:    ${host_label}"
  if [[ -n "$fqdn" || -n "$rdata" ]]; then
    echo "  Record:  ${fqdn}${rec_type:+ ${rec_type}}${rdata:+ ${rdata}}"
  fi
  [[ -n "$ttl" ]] && echo "  TTL:     ${ttl}"
  echo "  Message: ${_BC_MESSAGE}"
  case "$_BC_RELOAD" in
    success) echo -e "  Reload:  ${GREEN}BIND reloaded${NC}" ;;
    failed)  echo -e "  Reload:  ${RED}BIND reload FAILED — check service${NC}" ;;
    skipped) echo "  Reload:  skipped" ;;
    *)       echo "  Reload:  (no reload signal in output)" ;;
  esac
}

# Show help
function bc.help() {
  echo -e "${CYAN}⚓BindCaptain${NC} ${BC_PLUGIN_VERSION} - Chief Plugin"
  echo
  echo "  ⚓BindCaptain management: if BC_HOST is set, commands run there via SSH; if BC_HOST"
  echo "  is unset, commands run on this machine (useful when Chief runs on the DNS host)."
  echo
  echo "  Chief is a separate project. For more info (what it is, how to install, plugins):"
  echo "  https://github.com/randyoyarzabal/chief"
  echo
  echo -e "${WHITE}Available Commands:${NC}"
  echo
  echo -e "  ${GREEN}bc.create${NC} [A|CNAME|TXT] ... [--json]          Create DNS record (A default; clean summary or JSON)"
  echo -e "  ${GREEN}bc.update${NC} [A|CNAME|TXT] ... [--json]          Update DNS record (change IP/target/value/TTL); --json input also supported"
  echo -e "  ${GREEN}bc.create_cname${NC} <fqdn> <target> [--json]     Shortcut for 'bc.create CNAME ...'"
  echo -e "  ${GREEN}bc.create_txt${NC} <name> <domain> <value> [--json]   Shortcut for 'bc.create TXT ...'"
  echo -e "  ${GREEN}bc.delete${NC} <fqdn> [type] [--json]             Delete DNS record (clean summary or JSON)"
  echo -e "  ${GREEN}bc.list${NC} [domain] [--json|-j]               List records (all or specific; JSON optional)"
  echo -e "  ${GREEN}bc.refresh${NC} [--json]                          Refresh DNS config (clean summary or JSON)"
  echo -e "  ${GREEN}bc.sync_ptr${NC} [--json]                         Rebuild PTR zones from forward A records"
  echo -e "  ${GREEN}bc.git_refresh${NC}                               Update ⚓BindCaptain from Git"
  echo -e "  ${GREEN}bc.status${NC}                                    Show service status"
  echo -e "  ${GREEN}bc.start${NC} / ${GREEN}bc.stop${NC} / ${GREEN}bc.restart${NC}                  Service control"
  echo -e "  ${GREEN}bc.ssh${NC}                                       SSH to remote host"
  echo -e "  ${GREEN}bc.help${NC}                                      Show this help"
  echo
  echo -e "  Aliases: ${CYAN}bc.a${NC}=bc.create ${CYAN}bc.up${NC}=bc.update ${CYAN}bc.cname${NC}=bc.create_cname ${CYAN}bc.txt${NC}=bc.create_txt ${CYAN}bc.rm${NC}=bc.delete ${CYAN}bc.ls${NC}=bc.list"
  echo
  echo -e "${YELLOW}Examples:${NC}"
  echo "  bc.create webserver.example.com 192.0.2.100"
  echo "  bc.create webserver.example.com 192.0.2.100 --json"
  echo "  bc.create CNAME www.example.com webserver"
  echo "  bc.create TXT @ example.com \"v=spf1 -all\""
  echo "  bc.update webserver.example.com 192.0.2.200             # change IP"
  echo "  bc.update CNAME www.example.com newtarget                 # change CNAME target"
  echo "  bc.update --json '{\"type\":\"A\",\"fqdn\":\"web.example.com\",\"rdata\":\"192.0.2.200\",\"ttl\":3600}'"
  echo "  bc.list example.com"
  echo "  bc.list example.com --json"
  echo "  bc.delete webserver.example.com"
  echo "  bc.refresh"
  echo "  bc.sync_ptr"
  echo
  echo -e "${YELLOW}Configuration (current):${NC}"
  if [[ -n "$BC_HOST" ]]; then
    echo "  BC_HOST:    $BC_HOST  (SSH remote)"
  else
    echo "  BC_HOST:    (unset — local shell, no SSH)"
  fi
  echo "  BC_MANAGER: $BC_MANAGER"
}

# Internal: build the remote bash invocation that runs a manager function
# under non-interactive mode, with sudo, sourcing the manager. Args after
# the function name are passed verbatim (each separately %q-quoted).
_bc_remote_call() {
  local fn="$1"; shift
  local quoted=""
  local a
  for a in "$@"; do
    quoted+=" $(printf '%q' "$a")"
  done
  _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && $fn$quoted'"
}

# Internal: run a record-mutating manager call, capture output, classify,
# then emit either a human-friendly summary or JSON. Sets a non-zero exit
# on failure.
#
# Args:
#   $1  action   create|update|delete (label only)
#   $2  type     A|CNAME|TXT
#   $3  fqdn
#   $4  rdata    final IP / target / TXT value
#   $5  ttl      numeric or empty
#   $6  json     "true" | "false"
#   $7  fn       manager function name (e.g. bc.create_record)
#   $8+ args     args to pass to the manager function
_bc_run_record_action() {
  local action="$1" rec_type="$2" fqdn="$3" rdata="$4" ttl="$5" json="$6" fn="$7"
  shift 7
  local host_label
  if [[ -n "$BC_HOST" ]]; then host_label="$BC_HOST"; else host_label="local"; fi

  local raw exit_code
  raw="$(_bc_remote_call "$fn" "$@" 2>&1)"
  exit_code=$?

  local clean
  clean="$(_bc_strip_ansi <<<"$raw")"
  _bc_classify "$exit_code" <<<"$clean"

  if [[ "$json" == "true" ]]; then
    _bc_emit_json "$_BC_STATUS" "$action" "$rec_type" "$fqdn" "$rdata" "$ttl" \
      "$_BC_RELOAD" "$_BC_MESSAGE" "$exit_code" "$host_label" "$clean"
  else
    _bc_emit_summary "$action" "$rec_type" "$fqdn" "$rdata" "$ttl"
  fi
  return $exit_code
}

# Internal: run an arbitrary already-built remote bash script via _bc_ssh,
# capture+classify, and emit either a human-friendly summary or JSON. Used
# for non-record-shaped actions (delete, refresh, sync_ptr) where the
# record fields may be partially or wholly empty.
#
# Args:
#   $1 action     create|update|delete|refresh|sync_ptr (label only)
#   $2 type       A|CNAME|TXT or "" when not applicable
#   $3 fqdn       target FQDN or "" when not applicable
#   $4 rdata      target rdata or "" when not applicable
#   $5 ttl        numeric or ""
#   $6 json       "true"|"false"
#   $7 script     literal remote bash script (passed through `sudo bash -c <q>`)
_bc_run_remote() {
  local action="$1" rec_type="$2" fqdn="$3" rdata="$4" ttl="$5" json="$6" script="$7"
  local host_label
  if [[ -n "$BC_HOST" ]]; then host_label="$BC_HOST"; else host_label="local"; fi

  local raw exit_code
  raw="$(_bc_ssh "sudo bash -c $(printf '%q' "$script")" 2>&1)"
  exit_code=$?

  local clean
  clean="$(_bc_strip_ansi <<<"$raw")"
  _bc_classify "$exit_code" <<<"$clean"

  if [[ "$json" == "true" ]]; then
    _bc_emit_json "$_BC_STATUS" "$action" "$rec_type" "$fqdn" "$rdata" "$ttl" \
      "$_BC_RELOAD" "$_BC_MESSAGE" "$exit_code" "$host_label" "$clean"
  else
    _bc_emit_summary "$action" "$rec_type" "$fqdn" "$rdata" "$ttl"
  fi
  return $exit_code
}

# Create DNS record (A default; supports CNAME/TXT type dispatch).
# Captures remote output and reports a concise human-friendly summary
# (or a JSON object when --json is given).
function bc.create() {
  local USAGE="Usage: $FUNCNAME [A] <fqdn> <ip> [ttl] [--json]
       $FUNCNAME [A] <hostname> <domain> <ip> [ttl] [--json]
       $FUNCNAME CNAME <fqdn> <target> [--json]
       $FUNCNAME CNAME <alias> <domain> <target> [--json]
       $FUNCNAME TXT <name> <domain> <value> [--json]

Create DNS records and report success/failure plus reload status.

Options:
  --json    Emit a JSON object (status, action, record, reload, exit_code,
            host, message, raw) instead of a human-friendly summary.

Examples:
  $FUNCNAME webserver.example.com 192.0.2.100
  $FUNCNAME webserver.example.com 192.0.2.100 3600
  $FUNCNAME CNAME www.example.com webserver --json
  $FUNCNAME TXT @ example.com \"v=spf1 -all\""

  if [[ -z ${1:-} ]] || [[ $1 == "-?" ]] || [[ $1 == "--help" ]]; then
    echo "$USAGE"
    return 0
  fi

  # Pull out --json from anywhere in args
  local json_mode=false
  local positional=()
  local a
  for a in "$@"; do
    case "$a" in
      --json|-j) json_mode=true ;;
      *) positional+=("$a") ;;
    esac
  done
  set -- "${positional[@]}"

  local record_type="A"
  case "${1^^}" in
    A|CNAME|TXT)
      record_type="${1^^}"
      shift
      ;;
  esac

  _bc_check_connection || return 1

  case "$record_type" in
    A)
      # Forms accepted (TTL optional):
      #   <fqdn> <ip> [ttl]
      #   <hostname> <domain> <ip> [ttl]
      local fqdn ip ttl=""
      if [[ -z ${1:-} || -z ${2:-} ]]; then
        echo "$USAGE"; return 1
      fi
      # Heuristic: if $2 is an IPv4, treat as FQDN form; else hostname+domain form.
      if [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fqdn="$1"; ip="$2"; ttl="${3:-}"
      else
        if [[ -z ${3:-} ]]; then echo "$USAGE"; return 1; fi
        fqdn="$1.$2"; ip="$3"; ttl="${4:-}"
      fi
      local args=("$fqdn" "$ip")
      [[ -n "$ttl" ]] && args+=("$ttl")
      _bc_run_record_action "create" "A" "$fqdn" "$ip" "$ttl" "$json_mode" \
        "bc.create_record" "${args[@]}"
      ;;
    CNAME)
      # Forms: <fqdn> <target>  |  <alias> <domain> <target>
      local fqdn target
      if [[ -z ${1:-} || -z ${2:-} ]]; then echo "$USAGE"; return 1; fi
      if [[ -n ${3:-} ]]; then
        fqdn="$1.$2"; target="$3"
      else
        fqdn="$1"; target="$2"
      fi
      _bc_run_record_action "create" "CNAME" "$fqdn" "$target" "" "$json_mode" \
        "bc.create_cname" "$fqdn" "$target"
      ;;
    TXT)
      # Form: <name> <domain> <value>
      local name domain value fqdn
      if [[ -z ${1:-} || -z ${2:-} || -z ${3:-} ]]; then echo "$USAGE"; return 1; fi
      name="$1"; domain="$2"; value="$3"
      if [[ "$name" == "@" ]]; then fqdn="$domain"; else fqdn="${name}.${domain}"; fi
      _bc_run_record_action "create" "TXT" "$fqdn" "$value" "" "$json_mode" \
        "bc.create_txt" "$name" "$domain" "$value"
      ;;
    *)
      echo "✗ Unsupported record type: $record_type (supported: A, CNAME, TXT)"
      return 1
      ;;
  esac
}

# Update DNS record. Implemented as a delete-then-create on the remote host,
# wrapped in a single SSH session so BIND only reloads at the end. Supports
# A, CNAME, and TXT records, plus --json input and --json output.
#
# JSON input shape (any subset that identifies the target plus the new value):
#   { "type": "A|CNAME|TXT",
#     "fqdn": "host.example.com",
#     "rdata": "192.0.2.200",   # new IP / target / text value
#     "ttl":  3600                  # optional
#   }
#
# Positional forms mirror bc.create:
#   bc.update [A] <fqdn> <new_ip> [ttl]
#   bc.update CNAME <fqdn> <new_target>
#   bc.update TXT <name> <domain> <new_value>
function bc.update() {
  local USAGE="Usage: $FUNCNAME [A] <fqdn> <new_ip> [ttl] [--json]
       $FUNCNAME [A] <hostname> <domain> <new_ip> [ttl] [--json]
       $FUNCNAME CNAME <fqdn> <new_target> [--json]
       $FUNCNAME CNAME <alias> <domain> <new_target> [--json]
       $FUNCNAME TXT <name> <domain> <new_value> [--json]
       $FUNCNAME --json '<json-object>'         (JSON input form)

Update an existing DNS record by deleting and re-creating it on the remote
host in one round-trip (BIND reloads once, at the end).

Options:
  --json                     Emit a JSON object summary (output mode).
  --json '<json-object>'     Read the change from a JSON object on the
                             command line. Required keys: type, fqdn (or
                             name+domain), rdata. Optional: ttl. When the
                             argument immediately following --json starts
                             with '{', it is treated as JSON input.

Examples:
  $FUNCNAME web.example.com 192.0.2.200
  $FUNCNAME web.example.com 192.0.2.200 3600 --json
  $FUNCNAME CNAME www.example.com new-target
  $FUNCNAME TXT @ example.com 'v=spf1 -all'
  $FUNCNAME --json '{\"type\":\"A\",\"fqdn\":\"web.example.com\",\"rdata\":\"192.0.2.200\"}'"

  if [[ -z ${1:-} ]] || [[ $1 == "-?" ]] || [[ $1 == "--help" ]]; then
    echo "$USAGE"
    return 0
  fi

  # JSON input form: --json '{...}'
  local json_input=""
  local json_mode=false
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json|-j)
        json_mode=true
        # If the next arg looks like a JSON object, consume it as JSON input.
        if [[ -n "${2:-}" && "${2:0:1}" == "{" ]]; then
          json_input="$2"
          shift 2
        else
          shift
        fi
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done
  set -- "${positional[@]}"

  _bc_check_connection || return 1

  local rec_type="" fqdn="" rdata="" ttl="" name="" domain=""

  if [[ -n "$json_input" ]]; then
    # Parse JSON via python3 (broadly available); fall back to error if missing.
    if ! command -v python3 >/dev/null 2>&1; then
      echo "✗ --json input requires python3 in PATH on the local machine"
      return 1
    fi
    local parsed
    parsed=$(python3 - <<PYEOF "$json_input" 2>&1
import json, sys
try:
    obj = json.loads(sys.argv[1])
except Exception as e:
    print("ERR " + str(e)); sys.exit(2)
def g(k):
    v = obj.get(k, "")
    return "" if v is None else str(v)
print(g("type"))
print(g("fqdn"))
print(g("name"))
print(g("domain"))
print(g("rdata"))
print(g("ttl"))
PYEOF
)
    if [[ $? -ne 0 || "$parsed" == ERR* ]]; then
      echo "✗ Invalid JSON: $parsed"
      return 1
    fi
    {
      IFS= read -r rec_type
      IFS= read -r fqdn
      IFS= read -r name
      IFS= read -r domain
      IFS= read -r rdata
      IFS= read -r ttl
    } <<<"$parsed"
    if [[ -z "$fqdn" && -n "$name" && -n "$domain" ]]; then
      if [[ "$name" == "@" ]]; then fqdn="$domain"; else fqdn="${name}.${domain}"; fi
    fi
    rec_type="${rec_type^^}"
    [[ -z "$rec_type" ]] && rec_type="A"
  else
    # Positional form
    rec_type="A"
    case "${1^^}" in
      A|CNAME|TXT) rec_type="${1^^}"; shift ;;
    esac
    case "$rec_type" in
      A)
        if [[ -z ${1:-} || -z ${2:-} ]]; then echo "$USAGE"; return 1; fi
        if [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          fqdn="$1"; rdata="$2"; ttl="${3:-}"
        else
          if [[ -z ${3:-} ]]; then echo "$USAGE"; return 1; fi
          fqdn="$1.$2"; rdata="$3"; ttl="${4:-}"
        fi
        ;;
      CNAME)
        if [[ -z ${1:-} || -z ${2:-} ]]; then echo "$USAGE"; return 1; fi
        if [[ -n ${3:-} ]]; then fqdn="$1.$2"; rdata="$3"; else fqdn="$1"; rdata="$2"; fi
        ;;
      TXT)
        if [[ -z ${1:-} || -z ${2:-} || -z ${3:-} ]]; then echo "$USAGE"; return 1; fi
        name="$1"; domain="$2"; rdata="$3"
        if [[ "$name" == "@" ]]; then fqdn="$domain"; else fqdn="${name}.${domain}"; fi
        ;;
    esac
  fi

  if [[ -z "$fqdn" || -z "$rdata" ]]; then
    echo "✗ Missing required fields (need fqdn and rdata)"
    return 1
  fi
  case "$rec_type" in A|CNAME|TXT) ;; *) echo "✗ Unsupported record type: $rec_type"; return 1 ;; esac

  # For TXT: derive name/domain from fqdn if we still need them for the create call.
  if [[ "$rec_type" == "TXT" && ( -z "$name" || -z "$domain" ) ]]; then
    # Best-effort split: first label = name, rest = domain.
    name="${fqdn%%.*}"
    domain="${fqdn#*.}"
    [[ "$name" == "$fqdn" ]] && { name="@"; domain="$fqdn"; }
  fi

  # Build the remote create command tail (delete is uniform).
  local create_cmd
  case "$rec_type" in
    A)
      if [[ -n "$ttl" ]]; then
        create_cmd="bc.create_record $(printf '%q' "$fqdn") $(printf '%q' "$rdata") $(printf '%q' "$ttl")"
      else
        create_cmd="bc.create_record $(printf '%q' "$fqdn") $(printf '%q' "$rdata")"
      fi
      ;;
    CNAME)
      create_cmd="bc.create_cname $(printf '%q' "$fqdn") $(printf '%q' "$rdata")"
      ;;
    TXT)
      create_cmd="bc.create_txt $(printf '%q' "$name") $(printf '%q' "$domain") $(printf '%q' "$rdata")"
      ;;
  esac

  # Delete (typed) then create, in one remote bash invocation.
  local delete_cmd="bc.delete_record $(printf '%q' "$fqdn") $(printf '%q' "$rec_type")"
  local remote_script="export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && \
echo '--- bc.update: deleting existing record ---' && \
{ $delete_cmd || echo '(delete returned non-zero — record may not have existed; continuing)'; } && \
echo '--- bc.update: creating replacement record ---' && \
$create_cmd"

  local host_label
  if [[ -n "$BC_HOST" ]]; then host_label="$BC_HOST"; else host_label="local"; fi

  local raw exit_code
  raw="$(_bc_ssh "sudo bash -c $(printf '%q' "$remote_script")" 2>&1)"
  exit_code=$?

  local clean
  clean="$(_bc_strip_ansi <<<"$raw")"
  _bc_classify "$exit_code" <<<"$clean"

  if [[ "$json_mode" == "true" ]]; then
    _bc_emit_json "$_BC_STATUS" "update" "$rec_type" "$fqdn" "$rdata" "$ttl" \
      "$_BC_RELOAD" "$_BC_MESSAGE" "$exit_code" "$host_label" "$clean"
  else
    _bc_emit_summary "update" "$rec_type" "$fqdn" "$rdata" "$ttl"
  fi
  return $exit_code
}

# Internal: pull --json/-j out of args, leave positional in $@.
# Sets _BC_JSON to "true" or "false". Use:  eval "set -- $(_bc_extract_json "$@")"
# (Easier: assign via _bc_extract_json_into name args... — see callers.)
_bc_extract_json() {
  _BC_JSON=false
  _BC_POS=()
  local a
  for a in "$@"; do
    case "$a" in
      --json|-j) _BC_JSON=true ;;
      *) _BC_POS+=("$a") ;;
    esac
  done
}

# Shortcut: bc.create_cname <args> === bc.create CNAME <args>
function bc.create_cname() {
  if [[ ${1:-} == "-?" || ${1:-} == "--help" ]]; then
    echo "Usage: $FUNCNAME <fqdn> <target> [--json]"
    echo "       $FUNCNAME <alias> <domain> <target> [--json]"
    echo "Shortcut for: bc.create CNAME <args>"
    return 0
  fi
  bc.create CNAME "$@"
}

# Shortcut: bc.create_txt <args> === bc.create TXT <args>
function bc.create_txt() {
  if [[ ${1:-} == "-?" || ${1:-} == "--help" ]]; then
    echo "Usage: $FUNCNAME <name> <domain> <value> [--json]"
    echo "Shortcut for: bc.create TXT <args>"
    return 0
  fi
  bc.create TXT "$@"
}

# Delete DNS record (clean summary or JSON).
function bc.delete() {
  local USAGE="Usage: $FUNCNAME <fqdn> [type] [--json]
       $FUNCNAME <hostname> <domain> [type] [--json]
Delete a DNS record. Reports success/failure plus reload status.

Options:
  --json    Emit a JSON object summary instead of human-friendly text.

Examples:
  $FUNCNAME webserver.example.com
  $FUNCNAME webserver example.com
  $FUNCNAME www.example.com CNAME --json"

  if [[ -z ${1:-} ]] || [[ $1 == "-?" ]] || [[ $1 == "--help" ]]; then
    echo "$USAGE"; return 1
  fi

  _bc_extract_json "$@"
  set -- "${_BC_POS[@]}"

  _bc_check_connection || return 1

  # Resolve target FQDN + optional type. Mirrors original argument shapes.
  local fqdn rec_type=""
  if [[ -z ${2:-} ]] || [[ $2 =~ ^[A-Z]+$ ]]; then
    # <fqdn> [type]
    fqdn="$1"
    rec_type="${2:-}"
  else
    # <hostname> <domain> [type]
    fqdn="$1.$2"
    rec_type="${3:-}"
  fi

  # Build delete args (don't pass an empty type — the manager treats $# strictly).
  local fn_args=("$fqdn")
  [[ -n "$rec_type" ]] && fn_args+=("$rec_type")

  _bc_run_record_action "delete" "$rec_type" "$fqdn" "" "" "$_BC_JSON" \
    "bc.delete_record" "${fn_args[@]}"
}

# List DNS records
function bc.list() {
  local USAGE="Usage: $FUNCNAME [domain] [--json|-j]
List DNS records for all domains or a specific domain.

Options:
  --json, -j    Print records as a JSON array (stdout only; machine-readable)

Examples:
  $FUNCNAME                    # List all records
  $FUNCNAME example.com        # List example.com records only
  $FUNCNAME example.com --json # JSON output"

  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi

  local json_mode=false
  local arg
  for arg in "$@"; do
    if [[ $arg == "--json" || $arg == "-j" ]]; then
      json_mode=true
      break
    fi
  done

  _bc_check_connection || return 1

  if [[ $json_mode != true ]]; then
    local dom_seen=false
    for arg in "$@"; do
      [[ $arg == -* ]] && continue
      echo "Listing records for: ${arg}"
      dom_seen=true
      break
    done
    if [[ $dom_seen != true ]]; then
      echo "Listing all DNS records..."
    fi
  fi

  _bc_ssh "sudo bash -c 'source $BC_MANAGER && bc.list_records $(printf '%q ' "$@")'"
}

# Refresh DNS configuration (validate all zones + reload BIND).
function bc.refresh() {
  local USAGE="Usage: $FUNCNAME [--json]
Refresh and validate BIND DNS configuration, then reload.

This will:
  - Validate all zone files
  - Check BIND configuration
  - Reload BIND service if valid

Options:
  --json    Emit a JSON object summary instead of human-friendly text."

  if [[ ${1:-} == "-?" || ${1:-} == "--help" ]]; then
    echo "$USAGE"; return 0
  fi

  _bc_extract_json "$@"
  _bc_check_connection || return 1

  local script="export BIND_NONINTERACTIVE=1 && $BC_MANAGER refresh"
  _bc_run_remote "refresh" "" "" "" "" "$_BC_JSON" "$script"
}

# Rebuild lab PTR reverse zones from authoritative forward A records.
function bc.sync_ptr() {
  local USAGE="Usage: $FUNCNAME [--json]
Rewrite managed reverse zones (managed subnets) so PTRs match forward A records.

Use after imports or manual zone edits; bc.refresh runs this automatically.

Options:
  --json    Emit a JSON object summary instead of human-friendly text."

  if [[ ${1:-} == "-?" || ${1:-} == "--help" ]]; then
    echo "$USAGE"; return 0
  fi

  _bc_extract_json "$@"
  _bc_check_connection || return 1

  # Manager-side function name remains bc.sync_ptr_from_forwards.
  local script="export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.sync_ptr_from_forwards"
  _bc_run_remote "sync_ptr" "" "" "" "" "$_BC_JSON" "$script"
}

# Update ⚓BindCaptain from GitHub
function bc.git_refresh() {
  local USAGE="Usage: $FUNCNAME
Update ⚓BindCaptain codebase from Git (e.g. GitHub).

This will:
  - Pull latest changes from the remote repository
  - Preserve configuration files
  - Update scripts and tools"
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Updating ⚓BindCaptain from Git..."
  _bc_ssh "sudo bash -c 'cd \$(dirname \"$BC_MANAGER\")/.. && git pull'"
}

# SSH to remote ⚓BindCaptain host
function bc.ssh() {
  local USAGE="Usage: $FUNCNAME
Open an SSH connection to the ⚓BindCaptain host ($BC_HOST)."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  if [[ -z "$BC_HOST" ]]; then
    echo -e "${CYAN}BC_HOST is unset — you are already on the BindCaptain host (local mode).${NC}"
    return 0
  fi
  _bc_check_connection || return 1
  
  echo "Connecting to $BC_HOST..."
  ssh "$BC_HOST"
}

# Show ⚓BindCaptain status
function bc.status() {
  local USAGE="Usage: $FUNCNAME
Show ⚓BindCaptain service status and environment information."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  if [[ -n "$BC_HOST" ]]; then
    echo "⚓BindCaptain status on $BC_HOST:"
  else
    echo "⚓BindCaptain status (this host):"
  fi
  echo "=========================================="
  _bc_ssh "sudo systemctl status bindcaptain --no-pager -l"
  echo ""
  echo "Container Status:"
  echo "----------------"
  _bc_ssh "sudo podman ps -a --filter name=bindcaptain"
}

# Start ⚓BindCaptain service
function bc.start() {
  local USAGE="Usage: $FUNCNAME
Start the ⚓BindCaptain service on the remote host."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Starting ⚓BindCaptain service..."
  _bc_ssh "sudo systemctl start bindcaptain"
  echo "✓ ⚓BindCaptain service started"
  sleep 2
  bc.status
}

# Stop ⚓BindCaptain service
function bc.stop() {
  local USAGE="Usage: $FUNCNAME
Stop the ⚓BindCaptain service on the remote host."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Stopping ⚓BindCaptain service..."
  _bc_ssh "sudo systemctl stop bindcaptain"
  echo "✓ ⚓BindCaptain service stopped"
}

# Restart ⚓BindCaptain service
function bc.restart() {
  local USAGE="Usage: $FUNCNAME
Restart the ⚓BindCaptain service on the remote host."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Restarting ⚓BindCaptain service..."
  _bc_ssh "sudo systemctl restart bindcaptain"
  echo "✓ ⚓BindCaptain service restarted"
  sleep 2
  bc.status
}

# Aliases for convenience
alias bc.a='bc.create'
alias bc.up='bc.update'
alias bc.cname='bc.create_cname'
alias bc.txt='bc.create_txt'
alias bc.rm='bc.delete'
alias bc.ls='bc.list'

# Show quick help on load (stderr so stdout stays clean for bc.list --json | jq)
echo "⚓BindCaptain ${BC_PLUGIN_VERSION} loaded. Type 'bc.help' for usage." >&2
