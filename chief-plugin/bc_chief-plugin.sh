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
#   bc.refresh, bc.sync_ptr_from_forwards      - Refresh config / PTR rebuild from A records
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
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Show help
function bc.help() {
  echo -e "${CYAN}⚓BindCaptain${NC} - Chief Plugin"
  echo
  echo "  ⚓BindCaptain management: if BC_HOST is set, commands run there via SSH; if BC_HOST"
  echo "  is unset, commands run on this machine (useful when Chief runs on the DNS host)."
  echo
  echo "  Chief is a separate project. For more info (what it is, how to install, plugins):"
  echo "  https://github.com/randyoyarzabal/chief"
  echo
  echo -e "${WHITE}Available Commands:${NC}"
  echo
  echo -e "  ${GREEN}bc.create${NC} [A|CNAME|TXT] ...                  Create DNS record (A default)"
  echo -e "  ${GREEN}bc.create_cname${NC} <fqdn> <target>              Create CNAME record"
  echo -e "  ${GREEN}bc.create_txt${NC} <name> <domain> <value>        Create TXT record"
  echo -e "  ${GREEN}bc.delete${NC} <fqdn> [type]                      Delete DNS record"
  echo -e "  ${GREEN}bc.list${NC} [domain]                             List records (all or specific)"
  echo -e "  ${GREEN}bc.refresh${NC}                                   Refresh DNS config"
  echo -e "  ${GREEN}bc.sync_ptr_from_forwards${NC}                  Rebuild PTR zones from forward A records"
  echo -e "  ${GREEN}bc.git_refresh${NC}                               Update ⚓BindCaptain from Git"
  echo -e "  ${GREEN}bc.status${NC}                                    Show service status"
  echo -e "  ${GREEN}bc.start${NC} / ${GREEN}bc.stop${NC} / ${GREEN}bc.restart${NC}                  Service control"
  echo -e "  ${GREEN}bc.ssh${NC}                                       SSH to remote host"
  echo -e "  ${GREEN}bc.help${NC}                                      Show this help"
  echo
  echo -e "  Aliases: ${CYAN}bc.a${NC}=bc.create ${CYAN}bc.cname${NC}=bc.create_cname ${CYAN}bc.txt${NC}=bc.create_txt ${CYAN}bc.rm${NC}=bc.delete ${CYAN}bc.ls${NC}=bc.list"
  echo
  echo -e "${YELLOW}Examples:${NC}"
  echo "  bc.create webserver.example.com 172.25.50.100"
  echo "  bc.create CNAME www.example.com webserver"
  echo "  bc.create TXT @ example.com \"v=spf1 -all\""
  echo "  bc.create_cname www.example.com webserver"
  echo "  bc.create_txt @ example.com \"v=spf1 -all\""
  echo "  bc.list example.com"
  echo "  bc.delete webserver.example.com"
  echo "  bc.refresh"
  echo "  bc.sync_ptr_from_forwards"
  echo
  echo -e "${YELLOW}Configuration (current):${NC}"
  if [[ -n "$BC_HOST" ]]; then
    echo "  BC_HOST:    $BC_HOST  (SSH remote)"
  else
    echo "  BC_HOST:    (unset — local shell, no SSH)"
  fi
  echo "  BC_MANAGER: $BC_MANAGER"
}

# Create DNS record (A default; supports CNAME/TXT type dispatch)
function bc.create() {
  local USAGE="Usage: $FUNCNAME [A] <fqdn> <ip>
       $FUNCNAME [A] <hostname> <domain> <ip>
       $FUNCNAME CNAME <fqdn> <target>
       $FUNCNAME CNAME <alias> <domain> <target>
       $FUNCNAME TXT <name> <domain> <value>
Create DNS records from one entry point.

Examples:
  $FUNCNAME webserver.example.com 172.25.50.100
  $FUNCNAME CNAME www.example.com webserver
  $FUNCNAME TXT @ example.com \"v=spf1 -all\""

  if [[ -z ${1:-} ]] || [[ $1 == "-?" ]] || [[ $1 == "--help" ]]; then
    echo "$USAGE"
    return 0
  fi

  local record_type="A"
  case "${1^^}" in
    A|CNAME|TXT)
      record_type="${1^^}"
      shift
      ;;
  esac

  case "$record_type" in
    A)
      if [[ -z ${2:-} ]]; then
        echo "$USAGE"
        return 1
      fi
      _bc_check_connection || return 1

      # Support both FQDN and hostname+domain formats
      if [[ -z ${3:-} ]]; then
        # FQDN format: <fqdn> <ip>
        local fqdn="$1"
        local ip="$2"
        echo "Creating A record: ${fqdn} -> ${ip}"
        _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.create_record \"$fqdn\" \"$ip\"'"
      else
        # Traditional format: <hostname> <domain> <ip>
        local hostname="$1"
        local domain="$2"
        local ip="$3"
        echo "Creating A record: ${hostname}.${domain} -> ${ip}"
        _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.create_record \"$hostname\" \"$domain\" \"$ip\"'"
      fi
      ;;
    CNAME)
      bc.create_cname "$@"
      ;;
    TXT)
      bc.create_txt "$@"
      ;;
    *)
      echo "✗ Unsupported record type: $record_type (supported: A, CNAME, TXT)"
      return 1
      ;;
  esac
}

# Create CNAME record
function bc.create_cname() {
  local USAGE="Usage: $FUNCNAME <fqdn> <target>
       $FUNCNAME <alias> <domain> <target>
Create a CNAME record.

Examples:
  $FUNCNAME www.example.com webserver
  $FUNCNAME www example.com webserver"
  
  if [[ -z $2 ]] || [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 1
  fi
  
  _bc_check_connection || return 1
  
  # Support both FQDN and alias+domain formats
  if [[ -z $3 ]]; then
    # FQDN format: <fqdn> <target>
    local fqdn="$1"
    local target="$2"
    echo "Creating CNAME record: ${fqdn} -> ${target}"
    _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.create_cname \"$fqdn\" \"$target\"'"
  else
    # Traditional format: <alias> <domain> <target>
    local alias="$1"
    local domain="$2"
    local target="$3"
    echo "Creating CNAME record: ${alias}.${domain} -> ${target}"
    _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.create_cname \"$alias\" \"$domain\" \"$target\"'"
  fi
}

# Create TXT record
function bc.create_txt() {
  local USAGE="Usage: $FUNCNAME <name> <domain> <value>
Create a TXT record.

Example:
  $FUNCNAME @ example.com \"v=spf1 -all\""
  
  if [[ -z $3 ]] || [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 1
  fi
  
  local name="$1"
  local domain="$2"
  local value="$3"
  
  _bc_check_connection || return 1
  
  echo "Creating TXT record: ${name}.${domain} -> ${value}"
  _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.create_txt \"$name\" \"$domain\" \"$value\"'"
}

# Delete DNS record
function bc.delete() {
  local USAGE="Usage: $FUNCNAME <fqdn> [type]
       $FUNCNAME <hostname> <domain> [type]
Delete a DNS record.

Examples:
  $FUNCNAME webserver.example.com
  $FUNCNAME webserver example.com
  $FUNCNAME www.example.com CNAME"
  
  if [[ -z $1 ]] || [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 1
  fi
  
  _bc_check_connection || return 1
  
  # Support both FQDN and hostname+domain formats
  if [[ -z $2 ]] || [[ $2 =~ ^[A-Z]+$ ]]; then
    # FQDN format: <fqdn> [type] — do not pass an empty second arg (remote shell would see $#=2 as name+domain).
    local fqdn="$1"
    local type="${2:-}"
    echo "Deleting record: ${fqdn} ${type}"
    if [[ -n $type ]]; then
      _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.delete_record \"$fqdn\" \"$type\"'"
    else
      _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.delete_record \"$fqdn\"'"
    fi
  else
    # Traditional format: <hostname> <domain> [type]
    local hostname="$1"
    local domain="$2"
    local type="${3:-}"
    echo "Deleting record: ${hostname}.${domain} ${type}"
    if [[ -n $type ]]; then
      _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.delete_record \"$hostname\" \"$domain\" \"$type\"'"
    else
      _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.delete_record \"$hostname\" \"$domain\"'"
    fi
  fi
}

# List DNS records
function bc.list() {
  local USAGE="Usage: $FUNCNAME [domain]
List DNS records for all domains or a specific domain.

Examples:
  $FUNCNAME              # List all records
  $FUNCNAME example.com   # List example.com records only"
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  local domain="$1"
  
  _bc_check_connection || return 1
  
  if [[ -n $domain ]]; then
    echo "Listing records for: ${domain}"
    _bc_ssh "sudo bash -c 'source $BC_MANAGER && bc.list_records \"$domain\"'"
  else
    echo "Listing all DNS records..."
    _bc_ssh "sudo bash -c 'source $BC_MANAGER && bc.list_records'"
  fi
}

# Refresh DNS configuration
function bc.refresh() {
  local USAGE="Usage: $FUNCNAME
Refresh and validate BIND DNS configuration, then reload.

This will:
  - Validate all zone files
  - Check BIND configuration
  - Reload BIND service if valid"
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Refreshing ⚓BindCaptain DNS configuration..."
  _bc_ssh "sudo $BC_MANAGER refresh"
}

# Rebuild lab PTR reverse zones from authoritative forward A records
function bc.sync_ptr_from_forwards() {
  local USAGE="Usage: $FUNCNAME
Rewrite managed reverse zones (172.25.40/42/50) so PTRs match forward A records.

Use after imports or manual zone edits; bc.refresh runs this automatically."

  if [[ $1 == "-?" ]] || [[ $1 == "--help" ]]; then
    echo "$USAGE"
    return 0
  fi

  _bc_check_connection || return 1

  echo "Syncing PTR zones from forward A records..."
  _bc_ssh "sudo bash -c 'source $BC_MANAGER && bc.sync_ptr_from_forwards'"
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
alias bc.cname='bc.create_cname'
alias bc.txt='bc.create_txt'
alias bc.rm='bc.delete'
alias bc.ls='bc.list'

# Show quick help on load
echo "⚓BindCaptain loaded. Type 'bc.help' for usage."
