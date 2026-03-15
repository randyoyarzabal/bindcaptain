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
#   BC_HOST   - SSH target: user@host (e.g. root@dns.example.com).
#   BC_MANAGER - Absolute path to bindcaptain_manager.sh on the remote host
#                (e.g. /opt/bindcaptain/tools/bindcaptain_manager.sh).
#
#   To override: export BC_HOST and/or BC_MANAGER before loading the plugin, or
#   copy this file and change the default values below.
#
# INSTALLATION IN CHIEF
#   Ensure this file is installed as a Chief user plugin named "bc" (e.g. so
#   Chief loads it as the bc plugin). Edit with: chief.plugin bc
#   See Chief GitHub (link above) for plugin installation details.
#
# COMMANDS (see bc.help after loading)
#   bc.create, bc.create_cname, bc.create_txt  - Create DNS records
#   bc.delete, bc.list                         - Delete / list records
#   bc.refresh, bc.git_refresh                 - Refresh config / update from Git
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
BC_HOST="${BC_HOST:-root@your-bindcaptain-host}"
BC_MANAGER="${BC_MANAGER:-/opt/bindcaptain/tools/bindcaptain_manager.sh}"

# Internal function to execute remote commands
_bc_ssh() {
  ssh -q "$BC_HOST" "$@"
}

# Internal function to check if remote host is reachable
_bc_check_connection() {
  if ! ssh -q -o ConnectTimeout=3 "$BC_HOST" "exit" 2>/dev/null; then
    echo "✗ Error: Cannot connect to $BC_HOST"
    echo "  Ensure the host is reachable and SSH (e.g. key-based) is configured."
    return 1
  fi
  return 0
}

# Show help
function bc.help() {
  cat << 'EOF'
⚓ BindCaptain DNS Manager - Chief Plugin

  Remote BindCaptain management: commands run on the host configured in BC_HOST
  via SSH. Use this to manage DNS and the BindCaptain service from your local
  machine without logging into the server.

  Chief is a separate project. For more info (what it is, how to install, plugins):
  https://github.com/randyoyarzabal/chief

USAGE:
  bc.create <fqdn> <ip>                        Create A record (auto PTR)
  bc.create_cname <fqdn> <target>              Create CNAME record
  bc.create_txt <name> <domain> <value>        Create TXT record
  bc.delete <fqdn> [type]                      Delete DNS record
  bc.list [domain]                             List records (all or specific)
  bc.refresh                                   Refresh DNS config
  bc.git_refresh                               Update BindCaptain from Git
  bc.status                                    Show service status
  bc.start                                     Start service
  bc.stop                                      Stop service
  bc.restart                                   Restart service
  bc.ssh                                       SSH to remote host
  bc.help                                      Show this help

EXAMPLES:
  bc.create webserver.example.com 172.25.50.100
  bc.create_cname www.example.com webserver
  bc.create_txt @ example.com "v=spf1 -all"
  bc.list example.com
  bc.delete webserver.example.com
  bc.refresh

CONFIGURATION (current):
EOF
  echo "  BC_HOST:   $BC_HOST"
  echo "  BC_MANAGER: $BC_MANAGER"
}

# Create A record (and PTR)
function bc.create() {
  local USAGE="Usage: $FUNCNAME <fqdn> <ip>
       $FUNCNAME <hostname> <domain> <ip>
Create an A record and automatic PTR record.

Examples:
  $FUNCNAME webserver.example.com 172.25.50.100
  $FUNCNAME webserver example.com 172.25.50.100"
  
  if [[ -z $2 ]] || [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 1
  fi
  
  _bc_check_connection || return 1
  
  # Support both FQDN and hostname+domain formats
  if [[ -z $3 ]]; then
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
    # FQDN format: <fqdn> [type]
    local fqdn="$1"
    local type="${2:-}"
    echo "Deleting record: ${fqdn} ${type}"
    _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.delete_record \"$fqdn\" \"$type\"'"
  else
    # Traditional format: <hostname> <domain> [type]
    local hostname="$1"
    local domain="$2"
    local type="${3:-}"
    echo "Deleting record: ${hostname}.${domain} ${type}"
    _bc_ssh "sudo bash -c 'export BIND_NONINTERACTIVE=1 && source $BC_MANAGER && bc.delete_record \"$hostname\" \"$domain\" \"$type\"'"
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
  
  echo "Refreshing BindCaptain DNS configuration..."
  _bc_ssh "sudo $BC_MANAGER refresh"
}

# Update BindCaptain from GitHub
function bc.git_refresh() {
  local USAGE="Usage: $FUNCNAME
Update BindCaptain codebase from Git (e.g. GitHub).

This will:
  - Pull latest changes from the remote repository
  - Preserve configuration files
  - Update scripts and tools"
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Updating BindCaptain from Git..."
  _bc_ssh "sudo bash -c 'cd \$(dirname \"$BC_MANAGER\")/.. && git pull'"
}

# SSH to remote BindCaptain host
function bc.ssh() {
  local USAGE="Usage: $FUNCNAME
Open an SSH connection to the BindCaptain host ($BC_HOST)."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Connecting to $BC_HOST..."
  ssh "$BC_HOST"
}

# Show BindCaptain status
function bc.status() {
  local USAGE="Usage: $FUNCNAME
Show BindCaptain service status and environment information."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "BindCaptain Status on $BC_HOST:"
  echo "=========================================="
  _bc_ssh "sudo systemctl status bindcaptain --no-pager -l"
  echo ""
  echo "Container Status:"
  echo "----------------"
  _bc_ssh "sudo podman ps -a --filter name=bindcaptain"
}

# Start BindCaptain service
function bc.start() {
  local USAGE="Usage: $FUNCNAME
Start the BindCaptain service on the remote host."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Starting BindCaptain service..."
  _bc_ssh "sudo systemctl start bindcaptain"
  echo "✓ BindCaptain service started"
  sleep 2
  bc.status
}

# Stop BindCaptain service
function bc.stop() {
  local USAGE="Usage: $FUNCNAME
Stop the BindCaptain service on the remote host."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Stopping BindCaptain service..."
  _bc_ssh "sudo systemctl stop bindcaptain"
  echo "✓ BindCaptain service stopped"
}

# Restart BindCaptain service
function bc.restart() {
  local USAGE="Usage: $FUNCNAME
Restart the BindCaptain service on the remote host."
  
  if [[ $1 == "-?" ]]; then
    echo "$USAGE"
    return 0
  fi
  
  _bc_check_connection || return 1
  
  echo "Restarting BindCaptain service..."
  _bc_ssh "sudo systemctl restart bindcaptain"
  echo "✓ BindCaptain service restarted"
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
echo "⚓ BindCaptain DNS Manager loaded. Type 'bc.help' for usage."
